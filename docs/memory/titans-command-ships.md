# Titans and Command Ships

## Confirmed behavior

- All seven playable factions can build all seven Titans without foreign research requirements. Each individual Titan remains limited to one.
- The six non-Harbinger `native_*_titan` overrides deliberately use `target_filter_unit_type: cruiser` so AI players can replenish different Titans. Never change them back to `titan`.
- Exact foreign Titan definitions protected from small-ship instant-kill effects:
  - `native_trader_loyalist_titan`
  - `native_trader_rebel_titan`
  - `native_advent_loyalist_titan`
  - `native_advent_rebel_titan`
  - `native_vasari_loyalist_titan`
  - `native_vasari_rebel_titan`
- Advent Rebel Purification and Vasari Loyalist The Maw exclude exactly those six definitions. Never exclude all cruisers.
- Harbinger builds all six imported command ships. Those units use `build_kind: dlc3_herald_command_ship`, keeping production on the intended primary portal instead of ordinary factories.

## Architectural reason

The cruiser classification is an intentional AI workaround. Protect those ships through exact-definition ability exclusions, not by restoring Titan classification or granting every cruiser immunity.
