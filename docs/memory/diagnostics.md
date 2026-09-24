# Diagnostics and Entity Validation

## Uniforms

- Game 2.1.1 has an observed combined `unit_tags` capacity of 30. The base game uses 14; keep base plus mod at or below 30.
- Normal-starbase catalog isolation uses `item_access_tags`; register every access tag in the Uniform's `item_access_tags` array.
- A seventeenth custom unit tag was previously unavailable. Do not restore the four removed faction-starbase unit tags.

## Research-backed levels

- Removing only `build_prerequisites` is insufficient when `item_level_source` is `research_prerequisites_per_level`; foreign players still fail validation without the referenced research subjects.
- A technology-free base level uses `item_level_source: fixed_level_0` and `item_level_count: 1`.
- A referenced action data source must also use `level_count: 1`, with one entry in every level-dependent values or ratio array.

## Previously observed load failures

- Unregistered normal-starbase `unit_tag` values and custom unit-tag capacity overflow.
- Unregistered `item_access_tag` values after the access-tag migration.
- Missing Advent research subjects for Starbase Culture and Meteor Storm on foreign players.
- Meteor Storm item/action level-count mismatch.
- Vasari Hyperspace Engines validated against Advent starbases while its required unit tag was generic `starbase`.
- On 2026-09-24, the owner confirmed the game opened without a load error after the exact `vasari_starbase` Hyperspace Engines fix.

## Checks

- `tools/validate_mod.ps1` validates JSON, tags, ownership, Titan exclusions, Ancient Starbase availability, manifests, level alignment, limits, and starting assets.
- `tools/check_latest_log.ps1` reads only the newest game log and reports mod entity error blocks.
