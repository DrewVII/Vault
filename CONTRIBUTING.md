# Contributing to Vault

Thanks for considering a contribution. Vault is built to stay small, focused and well-engineered. The bar is quality over volume.

## Ground rules

- **No telemetry, no remote calls.** Vault is local-first. Any PR that introduces an outbound network call to a third party (other than `localhost` for Ollama and Hugging Face for the one-time WhisperKit model download) will be declined.
- **No dependencies unless justified.** Each added SwiftPM dependency must be argued in the PR description.
- **Match the existing style.** Read `AnalyticsEngine.swift` or `Store.swift` and write in the same idiom — concise, doc-commented, no clever abstractions.

## Workflow

1. Open an issue describing the problem or proposal before opening a PR for anything non-trivial.
2. Fork & create a branch from `main`: `feat/short-name` or `fix/short-name`.
3. Make the change. Keep the diff focused — one concern per PR.
4. Update `README.md` if behaviour changes, `CHANGELOG.md` for user-facing changes.
5. Verify the build:
   ```bash
   ./build.sh && open Vault.app
   ```
6. Open the PR with a clear summary and a short test plan.

## Code style

- **Swift API Design Guidelines** apply. No deviation needed.
- Doc comments (`///`) on every public type, function, and non-obvious property.
- Single-responsibility files. If a file passes ~400 lines, consider splitting.
- View files contain views, service files contain logic. Keep them apart.
- Prefer `struct` over `class` unless reference identity is required.
- Async work flows through `async/await` and `AsyncThrowingStream`. No completion handlers.

## Commit messages

Imperative mood, short subject, optional body:

```
Add CSV import for transactions

Support OFX 1.x format too. Parser is in Services/Importers/.
Tested with statements from BNP, BoursoBank, Revolut.
```

## Testing

Tests are not yet wired in (see the roadmap). If your PR adds non-trivial logic, please include a small test target or at minimum manual reproduction steps.

## License

By contributing you agree that your contribution will be released under the [MIT License](LICENSE).
