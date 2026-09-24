# Project Memory Index

`MEMORY_ARCHITECTURE_VERSION: 1`

This is a routing index, not a startup reading list. Memory architecture version 1 is frozen by the owner. Do not change its structure or retrieval workflow unless the owner explicitly revokes that freeze.

Search exact terms first:

```powershell
pwsh -File .\tools\search_memory.ps1 -Query "entity_or_error_text"
```

Read only the relevant topic:

- Titans, destructive abilities, command ships, primary portal: `memory/titans-command-ships.md`
- Starbases, Ancient Starbases, deployment, phase gates, range and limits: `memory/starbases.md`
- Component ownership and Vasari mobile infrastructure: `memory/components.md`
- Logs, Uniforms, entity validation, level sources and manifests: `memory/diagnostics.md`
- Starting resources, Git, assets and release packaging: `memory/economy-release.md`

Durable gameplay facts belong in an existing topic file and, whenever possible, in `tools/validate_mod.ps1`. Do not add another index, memory tier, or topic file.
