# Sunshine PR CI Pipeline

## What is it?
The set of automated checks that run on every pull request to `LizardByte/Sunshine`. Each check has its own pass criteria and its own failure modes. Knowing them ahead of time saves rounds of "fix → push → wait → red" iterations.

## Why it matters for Sunshine / TCC
Several of these checks have non-obvious rules (lambda line limits, function parameter caps, code-smell thresholds) that are not documented in `CONTRIBUTING.md` but will block a PR. Hitting them on the first push burns time. This file captures what we observed on PR #5094 so PR #2 can land cleaner.

## Key Concepts

### Checks observed on PR #5094 (May 2026)

| Check | What it enforces | Author can re-run? |
|-------|------------------|---------------------|
| **Semantic PR** | PR title follows Conventional Commits (`feat(scope): ...`) | Auto-passes when title is fixed |
| **SonarCloud Code Analysis** | Code quality gate — zero new code smells, zero new issues | No (re-runs on push) |
| **SonarCloud** (status check) | Metadata reporting; mirrors above | No |
| **Read the Docs (main)** | Builds the regular project docs site (`docs.lizardbyte.dev/.../sunshine`) | No (re-runs on push) |
| **Read the Docs (gh-pages)** | Builds a separate `gh-pages` variant via an external script | No (re-runs on push) |
| **Build matrix** (Linux/Windows/macOS/etc.) | Compiles + runs `test_sunshine` on each platform | Maintainers only — first-time contributors need approval before workflows run |

The build matrix may not appear immediately for first-time contributors — Sunshine requires a maintainer to approve workflow runs the first time. Until then, only the integrations that auto-run (Semantic PR, SonarCloud, Read the Docs) will show up.

### Re-running

PR authors **cannot** click "Re-run" on any check from the upstream repo (no write access). The only way to retrigger is to **push a new commit**. Pushing automatically re-runs all checks. Empty commits (`git commit --allow-empty -m "ci: trigger re-run"`) work but are usually flagged by the Semantic PR check unless `chore(ci):` or similar is used.

### SonarCloud rules that bit us

These thresholds are enforced even though they're not in any human-readable contributor doc:

| Rule | Threshold |
|------|-----------|
| `reinterpret_cast` should be replaced with safer alternative | Any use → code smell. Use `std::memcpy` for raw-byte → struct, `std::bit_cast` (C++20+) for trivially-copyable conversions. |
| `std::format` over manual concatenation (since C++20) | Multiple `+` of strings or `to_string()` calls in a return statement → smell. Use `std::format("...{}...", x)`. |
| Lambda max length | **20 lines.** Exceed → "Split into several lambdas/functions or make it a named function." |
| Function max parameters | **7.** Exceed → "brain-overload" smell. Solution: take a struct, use designated initializers (C++20+). |

The "Quality Gate" required value for new code smells is **0**. Even one smell in your diff fails the check. Existing smells in master are grandfathered.

### Read the Docs duplication

Sunshine has **two** Read the Docs builds: `sunshinestream` (main) and `lizardbyte-gh-pages-sunshine` (gh-pages variant, builds via a script downloaded from `LizardByte.github.io/scripts/readthedocs_build.sh`). The gh-pages one occasionally fails with the generic message:
```
Unknown problem
```
without further detail. When the **main** Read the Docs build passes and the gh-pages one fails with no useful error, treat as infrastructure flake — push again or ask a maintainer to re-run.

### Build matrix: first-PR gate

Sunshine workflows are configured with `pull_request_target` and require a maintainer to approve workflow runs for first-time contributors. This is a security measure (prevents fork-side workflow abuse). Symptoms:
- Your PR shows "Some checks haven't completed yet" indefinitely
- Only Semantic PR, SonarCloud, and Read the Docs show up
- Build matrix (Linux/Windows/etc.) is missing

Action: wait for a maintainer to approve, or `@`-mention one in a PR comment.

### What CI does NOT enforce (but you should still do)

- **clang-format**: there's a workflow file (`.github/workflows/cpp-clang-format-lint.yml`) but it's run on push, not strictly blocking. Still run it locally before pushing — reviewers will ask for it.
- **Coverage**: Codecov is used for visibility but I haven't observed it block PRs. Still write tests because the **Checklist** section of the PR template asks for them.

## Related
- [[contributing-guidelines]] — the official-ish rules
- [[dev-workflow]] — local build & test workflow
- LizardByte/Sunshine PR #5094 — the PR where these observations came from

## Sources
- Direct observation on PR #5094 (May 2026)
- `.github/semantic.yml` — semantic PR rules
- `.github/workflows/` — CI definitions
- SonarCloud rule descriptions (linked from each issue)
