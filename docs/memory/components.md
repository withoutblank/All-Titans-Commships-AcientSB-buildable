# Ship and Infrastructure Components

- Every ship can install only its own component family. Owning a foreign ship does not grant that ship the current player's native component family.
- Never expose component families through generic `capital_ship`, `titan`, `cruiser`, or `starbase` tags.
- Vasari Loyalist mobile infrastructure components appear only in `vasari_loyalist.player`.
- Those infrastructure components retain their Vasari Loyalist research requirements and may target native Vasari capital ships plus the Vasari starbase.
- `vasari_mobile_ruler_ship` is valid only on `vasari_loyalist_command_ship` and `vasari_starbase`.
- Normal-starbase catalog isolation details live in `starbases.md`; use item-access tags, not broad generic ownership.
