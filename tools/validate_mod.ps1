[CmdletBinding()]
param(
    [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$GameRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$failures = [System.Collections.Generic.List[string]]::new()
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    $script:checks++
    if (-not $Condition) {
        $script:failures.Add($Message)
    }
}

function Read-JsonFile {
    param([string]$Path)
    Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
}

function Read-Entity {
    param([string]$Name)
    Read-JsonFile (Join-Path (Join-Path $ModRoot "entities") $Name)
}

function Get-OptionalProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Has-ExactlyOnce {
    param([object[]]$Values, [string]$Expected)
    @($Values | Where-Object { $_ -eq $Expected }).Count -eq 1
}

if (-not (Test-Path -LiteralPath $ModRoot)) {
    throw "Mod root not found: $ModRoot"
}

$memoryArchitectureMarker = "MEMORY_ARCHITECTURE_VERSION: 1"
$agentRulesPath = Join-Path $ModRoot "AGENTS.md"
$memoryIndexPath = Join-Path $ModRoot "docs\PROJECT_MEMORY.md"
$memorySearchPath = Join-Path $ModRoot "tools\search_memory.ps1"
$requiredMemoryTopics = @(
    "titans-command-ships.md",
    "starbases.md",
    "components.md",
    "diagnostics.md",
    "economy-release.md"
)
Assert-True (Test-Path -LiteralPath $agentRulesPath) "Frozen memory router AGENTS.md is missing"
Assert-True (Test-Path -LiteralPath $memoryIndexPath) "Frozen project memory index is missing"
Assert-True (Test-Path -LiteralPath $memorySearchPath) "Memory retrieval script is missing"
if ((Test-Path -LiteralPath $agentRulesPath) -and (Test-Path -LiteralPath $memoryIndexPath)) {
    $agentRules = Get-Content -LiteralPath $agentRulesPath -Raw
    $memoryIndex = Get-Content -LiteralPath $memoryIndexPath -Raw
    Assert-True ($agentRules.Contains($memoryArchitectureMarker)) "AGENTS.md memory architecture version changed"
    Assert-True ($memoryIndex.Contains($memoryArchitectureMarker)) "Project memory index version changed"
    Assert-True ($agentRules -notmatch '(?i)read\s+.*PROJECT_MEMORY.*completely') "AGENTS.md restored full-memory startup loading"
    Assert-True (@(Get-Content -LiteralPath $memoryIndexPath).Count -le 30) "Project memory index is no longer a short router"
}
foreach ($topic in $requiredMemoryTopics) {
    Assert-True (Test-Path -LiteralPath (Join-Path $ModRoot "docs\memory\$topic")) "Frozen memory topic is missing: $topic"
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $gameCandidates = @(
        "D:\Program Files\Steam\steamapps\common\Sins2",
        "C:\Program Files (x86)\Steam\steamapps\common\Sins2",
        "C:\Program Files\Steam\steamapps\common\Sins2"
    )
    $GameRoot = $gameCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

Write-Host "Validating mod: $ModRoot"
if ($GameRoot) {
    Write-Host "Using base game: $GameRoot"
}

# Every data file in these folders is JSON. Syntax errors are always fatal.
foreach ($folder in @("entities", "uniforms", "localized_text")) {
    $folderPath = Join-Path $ModRoot $folder
    foreach ($file in Get-ChildItem -LiteralPath $folderPath -File) {
        try {
            Read-JsonFile $file.FullName | Out-Null
        }
        catch {
            $failures.Add("Invalid JSON: $($file.FullName): $($_.Exception.Message)")
        }
    }
}

$modUniformPath = Join-Path $ModRoot "uniforms\unit_tag.uniforms"
$modUniform = Read-JsonFile $modUniformPath
$baseUnitTags = @()
$baseItemAccessTags = @()
if ($GameRoot) {
    $baseUniform = Read-JsonFile (Join-Path $GameRoot "uniforms\unit_tag.uniforms")
    $baseUnitTags = @($baseUniform.unit_tags.name)
    $baseItemAccessTags = @(Get-OptionalProperty $baseUniform "item_access_tags")
}

$modUnitTags = @($modUniform.unit_tags.name)
$modItemAccessTags = @(Get-OptionalProperty $modUniform "item_access_tags")
$duplicateUnitTags = @($modUnitTags | Group-Object | Where-Object Count -gt 1)
$duplicateAccessTags = @($modItemAccessTags | Group-Object | Where-Object Count -gt 1)
Assert-True ($duplicateUnitTags.Count -eq 0) "Duplicate unit_tags in uniforms/unit_tag.uniforms"
Assert-True ($duplicateAccessTags.Count -eq 0) "Duplicate item_access_tags in uniforms/unit_tag.uniforms"
Assert-True ($modUnitTags.Count -le 16) "Mod declares $($modUnitTags.Count) unit tags; observed safe maximum is 16 custom tags"
if ($baseUnitTags.Count -gt 0) {
    Assert-True (($baseUnitTags.Count + $modUnitTags.Count) -le 30) "Combined unit tag count exceeds 30: base=$($baseUnitTags.Count), mod=$($modUnitTags.Count)"
}

$starbaseAccessTags = @(
    "titanpool_trader_starbase_components",
    "titanpool_advent_starbase_components",
    "titanpool_vasari_starbase_components",
    "titanpool_herald_starbase_components"
)
foreach ($tag in $starbaseAccessTags) {
    Assert-True (Has-ExactlyOnce $modItemAccessTags $tag) "Missing or duplicate item_access_tag registration: $tag"
}

$knownUnitTags = @($baseUnitTags + $modUnitTags | Sort-Object -Unique)
$knownAccessTags = @($baseItemAccessTags + $modItemAccessTags | Sort-Object -Unique)
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ModRoot "entities") -File -Filter "*.unit") {
    $unit = Read-JsonFile $file.FullName
    foreach ($tag in @(Get-OptionalProperty $unit "tags" | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        Assert-True ($knownUnitTags -contains $tag) "Unregistered unit_tag '$tag' in $($file.Name)"
    }
    foreach ($tag in @(Get-OptionalProperty $unit "item_access_tags" | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        Assert-True ($knownAccessTags -contains $tag) "Unregistered item_access_tag '$tag' in $($file.Name)"
    }
}
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ModRoot "entities") -File -Filter "*.unit_item") {
    $item = Read-JsonFile $file.FullName
    foreach ($tag in @(Get-OptionalProperty $item "required_unit_tags" | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        Assert-True ($knownUnitTags -contains $tag) "Unregistered required_unit_tag '$tag' in $($file.Name)"
    }
    foreach ($tag in @(Get-OptionalProperty $item "required_item_access_tags" | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })) {
        Assert-True ($knownAccessTags -contains $tag) "Unregistered required_item_access_tag '$tag' in $($file.Name)"
    }
    if ((Get-OptionalProperty $item "item_level_source") -eq "fixed_level_0") {
        Assert-True ($item.item_level_count -eq 1) "fixed_level_0 item must have item_level_count 1: $($file.Name)"
    }
}

$tecStarbaseItems = @(
    "trader_starbase_command_center", "trader_starbase_docking_booms", "trader_starbase_factory_support",
    "trader_starbase_flak_field", "trader_starbase_hangar_0", "trader_starbase_hangar_1",
    "trader_starbase_hangar_2", "trader_starbase_planetary_shield_array", "trader_starbase_self_destruct",
    "trader_starbase_structural_integrity_0", "trader_starbase_structural_integrity_1",
    "trader_starbase_structural_integrity_2", "trader_starbase_stun_torpedo", "trader_starbase_trade_port",
    "trader_starbase_unit_factory", "trader_starbase_unlock_beam_weapon", "trader_starbase_unlock_torpedo_weapon"
)
$adventStarbaseItems = @(
    "advent_starbase_area_shield", "advent_starbase_area_slow", "advent_starbase_culture",
    "advent_starbase_hangar_0", "advent_starbase_hangar_1", "advent_starbase_hangar_2",
    "advent_starbase_meteor_storm", "advent_starbase_planetary_shield_array", "advent_starbase_psi_projector",
    "advent_starbase_shield_booster", "advent_starbase_structural_integrity_0",
    "advent_starbase_structural_integrity_1", "advent_starbase_structural_integrity_2",
    "advent_starbase_unlock_missile_weapon", "advent_starbase_unlock_plasma_weapon",
    "advent_starbase_upgrade_missile_weapon", "advent_starbase_zealous_labor"
)
$vasariStarbaseItems = @(
    "vasari_starbase_charged_salvo", "vasari_starbase_debris_vortex", "vasari_starbase_hangar_0",
    "vasari_starbase_hangar_1", "vasari_starbase_hangar_2", "vasari_starbase_hyperspace_engines",
    "vasari_starbase_planetary_shield_array", "vasari_starbase_structural_integrity_0",
    "vasari_starbase_structural_integrity_1", "vasari_starbase_structural_integrity_2",
    "vasari_starbase_unlock_extra_phase_missile_weapons", "vasari_starbase_unlock_extra_wave_weapons",
    "vasari_starbase_upgrade_wave_weapons"
)
$heraldStarbaseItems = @(
    "dlc3_herald_starbase_consumption_matrix", "dlc3_herald_starbase_corruption",
    "dlc3_herald_starbase_hangar_0", "dlc3_herald_starbase_hangar_1", "dlc3_herald_starbase_hangar_2",
    "dlc3_herald_starbase_planetary_shield_array", "dlc3_herald_starbase_structural_integrity_0",
    "dlc3_herald_starbase_structural_integrity_1", "dlc3_herald_starbase_structural_integrity_2",
    "dlc3_herald_starbase_teleporter", "dlc3_herald_starbase_unlock_phase_cannon_weapon",
    "dlc3_herald_starbase_unlock_torpedo_weapon"
)
$starbaseSets = @(
    [pscustomobject]@{ Unit = "trader_starbase"; Access = $starbaseAccessTags[0]; Items = $tecStarbaseItems },
    [pscustomobject]@{ Unit = "advent_starbase"; Access = $starbaseAccessTags[1]; Items = $adventStarbaseItems },
    [pscustomobject]@{ Unit = "vasari_starbase"; Access = $starbaseAccessTags[2]; Items = $vasariStarbaseItems },
    [pscustomobject]@{ Unit = "dlc3_herald_starbase"; Access = $starbaseAccessTags[3]; Items = $heraldStarbaseItems }
)

foreach ($set in $starbaseSets) {
    $unit = Read-Entity "$($set.Unit).unit"
    Assert-True ((@($unit.item_access_tags) -join ",") -eq $set.Access) "$($set.Unit) item_access_tags changed"
    Assert-True ($null -eq (Get-OptionalProperty $unit.build "prerequisites")) "$($set.Unit) regained a build research prerequisite"
    foreach ($id in $set.Items) {
        $item = Read-Entity "$id.unit_item"
        $expectedUnitTag = if ($id -eq "vasari_starbase_hyperspace_engines") { "vasari_starbase" } else { "starbase" }
        Assert-True ((@($item.required_unit_tags) -join ",") -eq $expectedUnitTag) "$id must require $expectedUnitTag plus item access"
        Assert-True ((@($item.required_item_access_tags) -join ",") -eq $set.Access) "$id has the wrong starbase access tag"
        Assert-True ($null -eq (Get-OptionalProperty $item "build_prerequisites")) "$id regained a foreign research prerequisite"
        Assert-True ((Get-OptionalProperty $item "item_level_source") -ne "research_prerequisites_per_level") "$id still depends on faction research levels"
    }
}

$players = @(
    "trader_loyalist", "trader_rebel", "advent_loyalist", "advent_rebel",
    "vasari_loyalist", "vasari_rebel", "dlc3_herald"
)
$allStandardStarbaseItems = @($tecStarbaseItems + $adventStarbaseItems + $vasariStarbaseItems + $heraldStarbaseItems)
$playerObjects = @{}
foreach ($player in $players) {
    $definition = Read-Entity "$player.player"
    $playerObjects[$player] = $definition
    $components = @($definition.ship_components)
    $duplicates = @($components | Group-Object | Where-Object Count -gt 1)
    $duplicateNames = @($duplicates | ForEach-Object { $_.Name }) -join ", "
    Assert-True ($duplicates.Count -eq 0) "$player has duplicate ship_components: $duplicateNames"
    foreach ($id in $allStandardStarbaseItems) {
        Assert-True (Has-ExactlyOnce $components $id) "$player must contain standard starbase component exactly once: $id"
    }

}

$heraldPlanetLimits = @($playerObjects["dlc3_herald"].unit_limits.planet)
$heraldNormalStarbaseLimit = @($heraldPlanetLimits | Where-Object tag -eq "starbase")
$heraldAncientStarbaseLimit = @($heraldPlanetLimits | Where-Object tag -eq "dlc_ancient_starbase")
Assert-True ($heraldNormalStarbaseLimit.Count -eq 1 -and $heraldNormalStarbaseLimit[0].unit_limit -eq 3) "Harbinger planet starbase limit must be 3"
Assert-True ($heraldAncientStarbaseLimit.Count -eq 1 -and $heraldAncientStarbaseLimit[0].unit_limit -eq 2) "Harbinger Ancient Starbase limit must be 2"

$legacyAncientResearch = @(
    "trader_unlock_ancient_starbase",
    "advent_unlock_ancient_starbase",
    "vasari_unlock_ancient_starbase"
)
$researchManifest = Read-Entity "research_subject.entity_manifest"
foreach ($id in $legacyAncientResearch) {
    Assert-True (-not (Test-Path -LiteralPath (Join-Path (Join-Path $ModRoot "entities") "$id.research_subject"))) "Deleted Ancient Starbase research file was restored: $id"
    Assert-True (-not (@($researchManifest.ids) -contains $id)) "Ancient Starbase research remains in research_subject.entity_manifest: $id"
    foreach ($player in $players) {
        Assert-True (-not (@($playerObjects[$player].research.research_subjects) -contains $id)) "$player research tree still contains $id"
    }
}

$ancientStarbaseSets = @(
    [pscustomobject]@{ Unit = "trader_ancient_starbase"; Item = "trader_deploy_ancient_starbase" },
    [pscustomobject]@{ Unit = "advent_ancient_starbase"; Item = "advent_deploy_ancient_starbase" },
    [pscustomobject]@{ Unit = "vasari_ancient_starbase"; Item = "vasari_deploy_ancient_starbase" },
    [pscustomobject]@{ Unit = "dlc3_herald_ancient_starbase"; Item = "dlc3_herald_deploy_ancient_starbase" }
)
foreach ($set in $ancientStarbaseSets) {
    $unit = Read-Entity "$($set.Unit).unit"
    $item = Read-Entity "$($set.Item).unit_item"
    Assert-True ($null -eq (Get-OptionalProperty $unit.build "prerequisites")) "$($set.Unit) must have no research prerequisite"
    Assert-True ($null -eq (Get-OptionalProperty $item "build_prerequisites")) "$($set.Item) must have no research prerequisite"
}

$vasariInfrastructureItems = @(
    "vasari_mobile_civilian_research_lab", "vasari_mobile_exotic_factory", "vasari_mobile_fleet_beacon",
    "vasari_mobile_military_research_lab", "vasari_mobile_resonance_collector",
    "vasari_mobile_speed_research_lab", "vasari_mobile_ruler_ship"
)
foreach ($id in $vasariInfrastructureItems) {
    $owners = @($players | Where-Object { @($playerObjects[$_].ship_components) -contains $id })
    Assert-True (($owners -join ",") -eq "vasari_loyalist") "$id must belong only to vasari_loyalist.player; found: $($owners -join ', ')"
    $item = Read-Entity "$id.unit_item"
    Assert-True (@($item.required_unit_tags) -contains "vasari_starbase") "$id must support the Vasari starbase"
    Assert-True ($null -ne (Get-OptionalProperty $item "build_prerequisites")) "$id must retain the Vasari Loyalist research prerequisite"
}
$ruler = Read-Entity "vasari_mobile_ruler_ship.unit_item"
Assert-True ((@($ruler.required_unit_tags) -join ",") -eq "vasari_loyalist_command_ship,vasari_starbase") "Mobile Ruler Ship host tags changed"

$foreignTitans = @(
    "native_trader_loyalist_titan", "native_trader_rebel_titan",
    "native_advent_loyalist_titan", "native_advent_rebel_titan",
    "native_vasari_loyalist_titan", "native_vasari_rebel_titan"
)
foreach ($id in $foreignTitans) {
    $unit = Read-Entity "$id.unit"
    Assert-True ($unit.target_filter_unit_type -eq "cruiser") "$id must remain cruiser for AI replenishment"
}
foreach ($abilityFile in @("advent_rebel_titan_purification.action_data_source", "vasari_loyalist_titan_the_maw.action_data_source")) {
    $raw = Get-Content -LiteralPath (Join-Path (Join-Path $ModRoot "entities") $abilityFile) -Raw
    foreach ($id in $foreignTitans) {
        $occurrences = ([regex]::Matches($raw, [regex]::Escape('"' + $id + '"'))).Count
        Assert-True ($occurrences -ge 2) "$abilityFile must exclude exact foreign Titan $id in every destructive target filter"
    }
}

$heraldCommandShips = @(
    "herald_dlc2_trader_loyalist_super_capital_ship", "herald_dlc2_trader_rebel_super_capital_ship",
    "herald_dlc2_advent_loyalist_super_capital_ship", "herald_dlc2_advent_rebel_super_capital_ship",
    "herald_dlc2_vasari_loyalist_super_capital_ship", "herald_dlc2_vasari_rebel_super_capital_ship"
)
$heraldPlayer = $playerObjects["dlc3_herald"]
foreach ($id in $heraldCommandShips) {
    Assert-True (Has-ExactlyOnce @($heraldPlayer.buildable_units) $id) "Harbinger buildable_units missing $id"
    Assert-True (Has-ExactlyOnce @($heraldPlayer.faction_buildable_units) $id) "Harbinger faction_buildable_units missing $id"
    $unit = Read-Entity "$id.unit"
    Assert-True ($unit.build.build_kind -eq "dlc3_herald_command_ship") "$id must remain on the Harbinger command-ship/primary-portal build kind"
}

$meteorItem = Read-Entity "advent_starbase_meteor_storm.unit_item"
$cultureItem = Read-Entity "advent_starbase_culture.unit_item"
$meteorData = Read-Entity "advent_starbase_meteor_storm.action_data_source"
Assert-True ($meteorItem.item_level_count -eq 1 -and $meteorItem.item_level_source -eq "fixed_level_0") "Meteor Storm item must be fixed level 0 with one level"
Assert-True ($cultureItem.item_level_count -eq 1 -and $cultureItem.item_level_source -eq "fixed_level_0") "Starbase Culture item must be fixed level 0 with one level"
Assert-True ($meteorData.level_count -eq 1) "Meteor Storm action data source must have one level"
foreach ($value in @($meteorData.action_values)) {
    Assert-True (@($value.action_value.values).Count -eq 1) "Meteor Storm action value $($value.action_value_id) must contain one level"
    if ($null -ne (Get-OptionalProperty $value.action_value "ratio")) {
        Assert-True (@($value.action_value.ratio.ratio_values).Count -eq 1) "Meteor Storm ratio $($value.action_value_id) must contain one level"
    }
}

Assert-True (Test-Path -LiteralPath (Join-Path $ModRoot "entities\titanpool_vasari_deploy_phase_gate.ability")) "Custom phase-gate ability file is missing"
Assert-True (Test-Path -LiteralPath (Join-Path $ModRoot "entities\titanpool_vasari_phase_gate_structure.unit")) "Custom phase-gate unit file is missing"
$abilityManifest = Get-Content -LiteralPath (Join-Path $ModRoot "entities\ability.entity_manifest") -Raw
$unitManifest = Get-Content -LiteralPath (Join-Path $ModRoot "entities\unit.entity_manifest") -Raw
Assert-True ($abilityManifest -match 'titanpool_vasari_deploy_phase_gate') "Custom phase-gate ability missing from manifest"
Assert-True ($unitManifest -match 'titanpool_vasari_phase_gate_structure') "Custom phase-gate unit missing from manifest"

foreach ($file in Get-ChildItem -LiteralPath (Join-Path $ModRoot "entities") -Filter "unfair_*_start_mode.start_mode") {
    $mode = Read-JsonFile $file.FullName
    $tec = @($mode.faction_configurations | Where-Object player_definition_id -eq "trader_loyalist")[0]
    $vasari = @($mode.faction_configurations | Where-Object player_definition_id -eq "vasari_loyalist")[0]
    $herald = @($mode.faction_configurations | Where-Object player_definition_id -eq "dlc3_herald")[0]
    Assert-True ($herald.starting_assets.credits -eq $tec.starting_assets.credits) "$($file.Name): Harbinger credits must match TEC"
    Assert-True ($herald.starting_assets.metal -eq $vasari.starting_assets.metal) "$($file.Name): Harbinger metal must match Vasari"
    Assert-True ($herald.starting_assets.crystal -eq $vasari.starting_assets.crystal) "$($file.Name): Harbinger crystal must match Vasari"
    $vasariExotics = $vasari.starting_exotics | ConvertTo-Json -Compress -Depth 8
    $heraldExotics = $herald.starting_exotics | ConvertTo-Json -Compress -Depth 8
    Assert-True ($heraldExotics -eq $vasariExotics) "$($file.Name): Harbinger starting exotics must match Vasari"
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    & git -C $ModRoot diff --check 2>&1 |
        Where-Object { $_ -notmatch 'LF will be replaced by CRLF' } |
        ForEach-Object { Write-Host $_ }
    Assert-True ($LASTEXITCODE -eq 0) "git diff --check failed"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "REGRESSION VALIDATION FAILED ($($failures.Count) failures / $checks checks)" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host ""
Write-Host "REGRESSION VALIDATION PASSED ($checks checks)" -ForegroundColor Green
Write-Host "Unit tags: base=$($baseUnitTags.Count), mod=$($modUnitTags.Count), combined=$($baseUnitTags.Count + $modUnitTags.Count)"
Write-Host "Standard starbase components checked: $($allStandardStarbaseItems.Count) across $($players.Count) players"
exit 0
