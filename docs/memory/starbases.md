# Starbases and Ancient Starbases

## Normal starbases

- Every player owns all four normal-starbase component catalogs, but each starbase installs only its own catalog through these item-access tags:
  - TEC: `titanpool_trader_starbase_components`
  - Advent: `titanpool_advent_starbase_components`
  - Vasari: `titanpool_vasari_starbase_components`
  - Harbinger: `titanpool_herald_starbase_components`
- Register all four in `uniforms/unit_tag.uniforms.item_access_tags`. Do not create four extra unit tags.
- The Vasari starbase keeps the `vasari_starbase` unit tag for exact compatibility checks.
- `vasari_starbase_hyperspace_engines` requires exact unit tag `vasari_starbase` plus Vasari's item-access tag. Generic `starbase` makes the permission validator test `enable_can_hyperspace` against Advent starbases.
- Deployed normal starbases have no unavailable foreign research prerequisite.
- Starbase weapon ranges include the requested +5000 increase and must survive base-file refreshes.

## Ancient Starbases

- Ancient Starbases are technology-free for all seven factions.
- Deleted subjects `trader_unlock_ancient_starbase`, `advent_unlock_ancient_starbase`, and `vasari_unlock_ancient_starbase` stay absent from research trees, the manifest, and entity files.
- All four Ancient Starbase units and all four ship deployment components have no research prerequisite.
- Deployment icon assets remain in use even though the research subjects were removed.
- Harbinger planets allow three normal starbases and two Ancient Starbases. This is Harbinger-specific; do not force it onto the six original factions.

## Phase gate

- Foreign Vasari phase-gate deployment uses the technology-free custom pair `titanpool_vasari_deploy_phase_gate.ability` and `titanpool_vasari_phase_gate_structure.unit`.
