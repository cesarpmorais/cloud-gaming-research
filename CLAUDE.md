# TCC Project - Claude Instructions

## Knowledge Base

The `knowledge/` directory is a living documentation library of everything learned during this TCC project.
It is Obsidian-compatible (plain Markdown with `[[wikilinks]]`).

### Trigger
When the user says `knowledge` (or `knowledge: <topic>`), create or update a knowledge file.

### Ground Rules

1. **File naming** — kebab-case, e.g. `kms-drm.md`
2. **File placement** — choose the most appropriate category subfolder:
   - `protocols/` — networking and streaming protocols
   - `encoding/` — video/audio encoding concepts and codecs
   - `sunshine/` — Sunshine internals and architecture
   - `linux/` — Linux subsystems (KMS, DRM, evdev, etc.)
   - `contributions/` — our own changes, decisions, and reasoning
3. **Subfolders** — create a subfolder within a category when 3+ files share a clear sub-theme (e.g. `sunshine/build/`, `sunshine/ui/`)
4. **File structure** — every knowledge file must follow this template:
   ```
   # <Topic Name>

   ## What is it?
   Plain-english summary.

   ## Why it matters for Sunshine / TCC
   Relevance to the project.

   ## Key Concepts
   - term: definition

   ## Related
   - [[other-topic]]

   ## Sources
   - links, code file paths, docs
   ```
5. **INDEX.md** — always update `knowledge/INDEX.md` after creating or updating a file, reflecting the current structure
6. **Language** — English only
7. **New categories** — if a topic doesn't fit any existing category, create a new one and document it in INDEX.md
8. **Proactive suggestions** — after explaining a concept or answering a question, ask the user whether it should be added to the knowledge base. Never ask before explaining — always explain first.

## Ideas

Each idea lives in its own file under `ideas/` (e.g. `idea-05-virtual-display.md`), with `[[wikilinks]]` to related ideas and knowledge files to enable Obsidian graph visualization. `ideas/IDEAS.md` is the index.

### Trigger
When the user says `idea: <description>`, create a new `ideas/idea-NN-<slug>.md` file and add a row to `ideas/IDEAS.md`.

### Ground Rules

1. **File naming** — `idea-NN-<kebab-slug>.md`, e.g. `idea-06-new-feature.md`
2. **File structure** — every idea file must follow this template:
   ```
   # Idea: <Title>

   Status: 💡 raw

   ## Description
   What the idea is.

   ## Why it matters for TCC
   Impact, feasibility, PR potential.

   ## Related Ideas
   - [[idea-NN-other]]

   ## Related Knowledge
   - [[knowledge-topic]]
   ```
3. **INDEX.md** — always update `ideas/IDEAS.md` after creating or updating an idea, with a row linking to the file
4. **Status tags** — 💡 raw | 🔍 exploring | ✅ chosen | ❌ discarded
5. **Status updates** — when the user says `idea #N: <new status>`, update the status in both the idea file and `IDEAS.md`
6. **No deletions** — never remove ideas, only update their status
7. **Language** — English only

## Research Habits

When researching Sunshine features, issues, or implementation details:

1. **Always use the GitHub MCP** (`mcp__github__*` tools) instead of WebFetch for anything on GitHub.
2. **Always check Apollo** (`ClassicOldSong/Apollo`) alongside Sunshine — Apollo is the main active fork and often has features not yet in Sunshine. Check if a feature already exists there before proposing it.
3. **Check both repos for issues and PRs** before logging a new idea, to avoid duplicating existing work.

## Sunshine Contribution Rules

When writing or suggesting C++ code changes for Sunshine:

1. **Code style** — always follow `.clang-format` rules (no manual style choices). Run `python ./scripts/update_clang_format.py` to auto-fix before committing.
2. **PR titles** — must use Conventional Commits format: `type(scope): description`. Common types: `feat`, `fix`, `refactor`, `docs`, `test`. Example: `fix(capture): add 10-bit pixel format support in portalgrab`.
3. **Tests** — new code should have Google Test (`gtest`) tests in `./tests/`. If GPU-dependent, add gcovr exclusion markers and note that CI won't cover it.
4. **Build dir** — use `cmake-build-` prefix for build directories (e.g. `cmake-build-debug`).
5. **Localization** — any user-facing string in C++ must use `boost::locale::translate()`; in Vue UI use `$t('key')` and only add to `en.json`.
