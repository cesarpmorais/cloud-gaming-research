# Sunshine Dev Workflow

## What is it?
Step-by-step guide for building, running, testing, and contributing to Sunshine from source on Fedora/Linux. Based on lessons learned during TCC setup.

## Why it matters for Sunshine / TCC
Avoids repeating the same setup mistakes. Covers the gotchas we hit (root-owned build files, setcap, CUDA, display detection).

## Key Concepts

### 1. Linux build dependencies (Fedora 43, post-May 2026 upstream)

The May 2026 upstream merge (see [[xdgportal-pipewire-migration]]) tightened the dependency surface. On a fresh Fedora 43, expect to install:

| Package | Why |
|---------|-----|
| `gcc-c++` | C++ compiler (Fedora ships only `gcc` for C by default) |
| `vulkan-loader-devel` | Provides `libvulkan.so` symlink — required even if you don't use the Vulkan encoder |
| `glslang` | Provides `glslangValidator` for compiling Vulkan shaders during build |
| `libstdc++-static` | Sunshine statically links libstdc++ on Linux now |
| `iproute-tc` | For `tc netem` (testbed setup, optional) |

If you see `libvulkan not found`, `Vulkan shader compiler not found`, `cannot locate -lstdc++`, or `No CMAKE_CXX_COMPILER could be found`, install the corresponding package above.

### 2. Clone and build

```bash
git clone --recurse-submodules https://github.com/LizardByte/Sunshine.git
cd Sunshine

# Disable CUDA unless you have a working CUDA toolkit + unlocked NVFBC.
# CUDA became mandatory by default in May 2026 — without this flag, configure fails with "CUDA not found".
cmake -B build -G Ninja -S . -DSUNSHINE_ENABLE_CUDA=OFF
ninja -C build
```

**Build dir convention:** project guidelines prefer `cmake-build-` prefix (e.g. `cmake-build-debug`). `build/` works locally.

**Submodules drift:** if `git pull` (or "Update branch" in the GitHub UI) leaves "(new commits)" markers on submodules in `git status`, run `git submodule update --init --recursive` to sync local checkouts to the new parent pointers. Stale submodules cause cryptic build errors (e.g. `nvenc_base.cpp` failing to compile because the bundled `nv-codec-headers` is at v12 while the parent expects v13).

### 3. Install (needed once for assets/apps.json)

```bash
sudo ninja -C build install
```

**Gotcha:** this runs as root, so files copied into `build/` become root-owned. After install, fix permissions:

```bash
sudo chown -R $(whoami):$(whoami) build/
```

Otherwise future `ninja -C build` will fail with "Permission denied" on test config files.

### 4. Set capabilities

Sunshine needs Linux capabilities for KMS capture and thread priority:

```bash
sudo setcap cap_sys_admin,cap_sys_nice+ep $(readlink -f ./build/sunshine)
```

**Gotcha:** `setcap` fails with "Invalid file" if the binary is on a filesystem without xattr support. Workaround: copy to `/tmp`, setcap there, copy back.

Note: a recent upstream change (#5075) drops `CAP_SYS_ADMIN` when possible, retaining only `CAP_SYS_NICE`. `setcap` is still required for the latter.

### 5. Configure

Config file: `~/.config/sunshine/sunshine.conf`

Key settings:
```
capture = portal    # or x11, wlr, kwin, kms, nvfbc — see [[capture-backends]] for the full list
```

### 6. Run

```bash
# Must be run from within a graphical session (X11 or Wayland)
# DISPLAY or WAYLAND_DISPLAY must be set
sunshine

# With debug logging (useful when testing changes)
sunshine --log-level debug
```

**Gotcha:** if `DISPLAY` is not set (SSH, wrong TTY), Sunshine fails with:
```
Fatal: Unable to find display or encoder during startup.
```
Always run from a terminal inside your desktop session.

### 7. Test streaming

1. Open `http://localhost:47990` in a browser → Sunshine Web UI
2. Install Moonlight on your phone/client device
3. On Moonlight, add your PC's IP address
4. Pair using the PIN shown in the Sunshine Web UI
5. Stream

### 8. Run tests

```bash
./build/tests/test_sunshine

# Filter to a specific test group
./build/tests/test_sunshine --gtest_filter='MetricsCsvTests.*'
```

`ctest --output-on-failure` from the build dir may report "No tests were found" — that's a known cmake registration quirk. Run the binary directly.

### 9. Format code before committing

Requires `clang-format` (provided by `clang-tools-extra` on Fedora):

```bash
python ./scripts/update_clang_format.py
```

The script has no shebang — always invoke via `python` explicitly. **Never run with `./script.py`** in bash, because the python `import os` and `import subprocess` lines get interpreted by bash, and on systems with ImageMagick installed, `import` is the screenshot command — you'll end up with PostScript files named `os` and `subprocess` in your repo root.

### 10. Rebuild after changes

```bash
ninja -C build
```

Ninja only recompiles changed files. No need to re-run cmake unless you changed CMakeLists.txt or added new files.

### 11. Switching between X11 and Wayland

At the KDE login screen (SDDM), click the session selector (bottom-left) to pick "Plasma (X11)" or "Plasma (Wayland)".

- **X11**: `capture = x11` — always works, reliable
- **Wayland**: `capture = portal` — goes through PipeWire; where the 10-bit bug lives

After switching sessions, verify:
```bash
echo $DISPLAY          # X11: should show :0 or :1
echo $WAYLAND_DISPLAY  # Wayland: should show wayland-0 or similar
```

### Common errors and fixes

| Error | Cause | Fix |
|-------|-------|-----|
| `Unable to find display or encoder` | No `DISPLAY` set | Run from graphical session |
| `Couldn't scale frame: Invalid argument` | 10-bit format not in `format_map` (now in `pipewire.cpp`) | See [[fix-10bit-portal/plan]] — partial upstream fix exists |
| `Permission denied` on build | Root-owned files from `sudo install` | `sudo chown -R $(whoami) build/` |
| `setcap: Invalid file` | Filesystem without xattr | Copy binary to `/tmp`, setcap, copy back |
| `All encoders failed` | Wrong capture backend for session type | Match `capture =` to your session |
| `No CMAKE_CXX_COMPILER could be found` | Missing `gcc-c++` | `sudo dnf install gcc-c++` |
| `libvulkan not found` | Missing Vulkan headers symlink | `sudo dnf install vulkan-loader-devel` |
| `Vulkan shader compiler not found` | Missing glslang | `sudo dnf install glslang` |
| `cannot locate -lstdc++` | Missing static libstdc++ | `sudo dnf install libstdc++-static` |
| `CUDA not found` (during cmake) | CUDA mandatory by default since May 2026 | Add `-DSUNSHINE_ENABLE_CUDA=OFF` to cmake |
| NVENC compile errors (`NV_ENC_SPLIT_ENCODE_MODE` etc.) | Stale `nv-codec-headers` submodule (v12 vs v13 mismatch) | `git submodule update --init --recursive` |
| `Using existing FFmpeg binaries` after upstream merge → linker errors | Stale FFmpeg cache in `_deps/` | `rm -rf build && cmake -B build -G Ninja ...` |

## Related
- [[architecture]]
- [[capture-backends]]
- [[contributing-guidelines]]
- [[sunshine-ci-pipeline]] — the checks your PR will hit
- [[xdgportal-pipewire-migration]] — context behind the new build deps

## Sources
- Sunshine docs: `docs/building.md`, `docs/getting_started.md`
- Hands-on experience during TCC setup
