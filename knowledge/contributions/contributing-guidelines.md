# Sunshine Contributing Guidelines

## What is it?
The rules and processes LizardByte enforces for all PRs to Sunshine. These are enforced by CI — a PR that violates them will be blocked automatically.

The full org-level guide lives at `https://docs.lizardbyte.dev/latest/developers/contributing.html`.
The project-level guide is at `docs/contributing.md` in the repo.

## Why it matters for Sunshine / TCC
Any TCC contribution must go through a PR that passes all these checks before maintainers will review it. Knowing the rules upfront avoids wasted cycles on fixable CI failures.

## Key Concepts

### PR Title — Semantic / Conventional Commits (enforced by CI)
- PR titles **must** follow [Conventional Commits](https://www.conventionalcommits.org/) format
- Format: `type(scope): short description`
- Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`
- Enforced by `.github/semantic.yml` via the `semantic-prs` GitHub App
- Sunshine uses **squash-and-merge**, so the PR title becomes the commit message
- Example: `fix(capture): add 10-bit pixel format support in portalgrab`

### Code Style — clang-format (enforced by CI)
- All C/C++ code is linted against `.clang-format` at the repo root
- CI workflow: `.github/workflows/cpp-clang-format-lint.yml`
- Auto-fix locally:
  ```bash
  python ./scripts/update_clang_format.py
  # or
  find ./ -iname *.cpp -o -iname *.h | xargs clang-format -i
  ```
- Recommended IDE: **CLion** (free for non-commercial use; respects `.clang-format` natively)

### Testing — Google Test (gtest)
- Test framework: **Google Test** (included as a submodule)
- Test sources: `./tests/` directory
- Test binary after build: `./build/tests/test_sunshine`
- Build option to disable tests: `-DBUILD_TESTS=OFF`
- Run tests: `./build/tests/test_sunshine`
- Coverage tool: **gcovr** + **Codecov**
- **Codecov will fail a PR** if total coverage drops too much, or if the diff isn't covered enough
- GPU-dependent tests can't run in CI runners — exclude them with gcovr markers:
  ```cpp
  // GCOVR_EXCL_START
  ...gpu-dependent code...
  // GCOVR_EXCL_STOP
  ```
- Write tests even for GPU-dependent code — maintainers can run them locally

### Build Conventions
- Build directories must be prefixed with `cmake-build-` (e.g. `cmake-build-debug`)
- On Linux: standard CMake + Ninja workflow
- On Windows: uses msys2/ucrt64 (prefix all commands with `C:\msys64\msys2_shell.cmd -defterm -here -no-start -ucrt64 -c`)

### Localization
- **Only add new strings to `en.json`** — never edit other language files
- Web UI: use Vue I18n (`$t('key.name')`)
- C++: use `boost::locale::translate("string")`
- JSON keys must be sorted alphabetically
- Translations happen automatically via CrowdIn after merge

### Web UI Stack (if contributing to the UI)
- Build system: Vite
- Framework: Vue.js
- CSS: Bootstrap
- Templating: EJS (`template_header.html`, `template_header_main.html`)
- Pages: `./src_assets/common/assets/web/`

## Related
- [[architecture]]
- [[capture-backends]]

## Sources
- `docs/contributing.md` in the Sunshine repo
- `.github/semantic.yml` — PR title enforcement config
- `.github/copilot-instructions.md` — build/test conventions
- `https://docs.lizardbyte.dev/latest/developers/contributing.html` (org-level guide; may require VPN/direct access)
