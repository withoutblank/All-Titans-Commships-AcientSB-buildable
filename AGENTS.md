# All Titans & Command Ships + Ancient Starbases — Agent Router

`MEMORY_ARCHITECTURE_VERSION: 1`

This is the live local Sins II mod. The owner has frozen memory architecture version 1. Do not change its routing model, required files, or retrieval workflow unless the owner explicitly revokes that freeze.

## Retrieve only what the task needs

- Never preload or read every memory document.
- Search first with `tools/search_memory.ps1 -Query '<error, entity id, or feature>'`.
- Read only matching topic documents; normally one, at most two unless the task spans more systems.
- Use `docs/PROJECT_MEMORY.md` only as a short routing index when the topic is ambiguous.
- Routes:
  - Titans, instant-kill exclusions, command ships, Harbinger portal → `docs/memory/titans-command-ships.md`
  - Starbases, Ancient Starbases, deployment, phase gates, range, limits → `docs/memory/starbases.md`
  - Ship/component ownership and Vasari mobile infrastructure → `docs/memory/components.md`
  - Logs, Uniforms, validation, fixed levels, manifests → `docs/memory/diagnostics.md`
  - Starting resources, Git, release assets, packaging → `docs/memory/economy-release.md`
- Add durable facts to the existing matching topic and, when enforceable, `tools/validate_mod.ps1`. Do not add another memory layer or topic file.

## Always-observed boundaries

- Preserve unrelated user changes, especially `.mod_meta_data`, both logo PNG files, and release ZIP files. Inspect status only for task-relevant files; never reset unrelated work.
- Compare changed base-game overrides with definitions under `D:\Program Files\Steam\steamapps\common\Sins2`.
- Base overrides do not belong in manifests; only genuinely new custom IDs do.
- Do not commit or push unless explicitly asked. Push only to the authorized branch.

## Verification

- After entity, Uniform, localization, or memory-contract changes, run `tools/validate_mod.ps1`; zero failures are required.
- When an error is reported, run `tools/check_latest_log.ps1` and fix the newest concrete mod error.
- Run `git diff --check` before completion.
- Report static verification separately from runtime testing. Never claim runtime success from JSON validation alone.
