# 贴边 · EdgePeek

- Native macOS app using SwiftUI for presentation and AppKit for panels and mouse handling. Shared data and persistence live in `EdgePeekCore`; the one-shot CLI used by the bundled Skill uses the same JSON store.
- Keep changes small and preserve local data. Run UI checks with `EDGEPEEK_DATA_FILE` pointing to a temporary file.
- Run `swift test` for behavior changes. AppKit and layout regressions belong in `Tests/EdgePeekTests`; shared model tests belong in `Tests/EdgePeekCoreTests`.
- Keep `README.md` and relevant `docs/` aligned with durable behavior changes.

## Documentation index

- [docs/interactions.md](docs/interactions.md): board headers, editor controls, native dragging, deletion/undo behavior, edge-light animations and click-through halo windows, and regression acceptance steps.
- [docs/skill.md](docs/skill.md): Skill installation, CLI commands, data sharing, and troubleshooting.
- [docs/preview.png](docs/preview.png): visual reference captured before the current top-of-group label layout; not a current layout acceptance image.
- [docs/release.md](docs/release.md): pushed-source gates, universal builds, Developer ID signing, notarization, public GitHub Releases, the delivery.json release probe, and installation verification.
