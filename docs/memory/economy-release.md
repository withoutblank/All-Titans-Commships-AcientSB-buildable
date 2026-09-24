# Economy, Git, and Release

## Starting resources

- Harbinger start modes use TEC starting credits.
- Harbinger start modes use Vasari starting metal, crystal, and all exotic-material quantities, including Quarnium-equivalent rare resources.
- These values belong in `unfair_*_start_mode.start_mode` faction configurations, not player default assets.

## Repository and release boundaries

- Preserve unrelated user changes, especially `.mod_meta_data`, `mod_large_logo.png`, `mod_small_logo.png`, and release ZIP files.
- Do not commit or push unless explicitly asked. Push only to the explicitly authorized branch.
- Base-game entity overrides are discovered by existing IDs and do not belong in manifests. Add only genuinely new custom IDs.
- Keep commits focused and reversible when a commit is requested.
