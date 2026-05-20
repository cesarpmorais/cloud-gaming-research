# Sunshine Architecture Overview

## What is it?
Sunshine is a self-hosted game streaming server written in C++. It implements the host side of the Moonlight/GameStream protocol: it captures the screen, encodes video, and transmits it over the network to a Moonlight client (phone, TV, another PC). Input (keyboard, mouse, gamepad) flows in the reverse direction.

The codebase is cross-platform (Linux, Windows, macOS) with a clear platform abstraction layer. The `platf::` namespace in `src/platform/common.h` defines abstract interfaces; each OS has its own implementation under `src/platform/<os>/`.

---

## Pipeline

```
[Display / GPU]
      │
      ▼
 CAPTURE STAGE          src/platform/linux/{x11grab,wlgrab,portalgrab,kmsgrab,cuda}.cpp
      │  raw frames (AVFrame)
      ▼
 ENCODE STAGE           src/video.cpp  +  src/nvenc/  +  FFmpeg (libavcodec)
      │  encoded packets (H.264 / HEVC / AV1)
      ▼
 STREAM STAGE           src/stream.cpp
      │  Moonlight UDP packets (with Reed-Solomon FEC)
      ▼
 NETWORK STAGE          src/rtsp.cpp  +  src/nvhttp.cpp  +  src/network.cpp
      │
      ▼
[Moonlight client]
      │  input events (keyboard, mouse, gamepad)
      ▼
 INPUT STAGE            src/input.cpp  →  uinput / evdev (Linux)
```

---

## Subsystems and Key Files

### Startup (`src/main.cpp`)
Orchestrates initialization. Starts three long-lived threads:
- `nvhttp::start` — GameStream HTTP API (pairing, device discovery; port 47989)
- `confighttp::start` — Web UI (port 47990)
- `rtsp_stream::start` — RTSP session negotiation (port 48010)

Also initializes: platform layer, process manager, input, encoder probe, mDNS, UPnP.

### Capture (`src/platform/linux/`)
Platform-specific. Each backend implements the `platf::display_t` abstract interface.

| File | Backend | When used |
|------|---------|-----------|
| `x11grab.cpp` | x11 | X11 session |
| `wlgrab.cpp` | wlr | Wayland + wlroots compositor |
| `portalgrab.cpp` | portal | Wayland via PipeWire/xdg-desktop-portal |
| `kmsgrab.cpp` | kms | Any session (needs `cap_sys_admin`) |
| `cuda.cpp` / `cuda.cu` | nvfbc | NVIDIA GPU only |

### Encode (`src/video.cpp` + `src/nvenc/`)
- Probes available encoders at startup (`video::probe_encoders()`)
- Supports software (x264/x265 via FFmpeg) and hardware (NVENC, VAAPI, VideoToolbox)
- `nvenc/` is a self-contained wrapper for NVIDIA's NVENC SDK
- Converts captured frames to the codec's input format via `sws_scale` / VAAPI filters

### Stream (`src/stream.cpp`)
- Implements the Moonlight streaming protocol on top of `moonlight-common-c`
- Video over UDP with Reed-Solomon forward error correction (`rswrapper`)
- Control channel (IDR requests, per-frame FEC status, HDR mode, input, rumble, etc.)
- Sunshine extends the protocol with custom packet types (0x55xx range) for features like RGB LEDs and adaptive triggers

### Session / Pairing (`src/nvhttp.cpp`, `src/rtsp.cpp`, `src/httpcommon.cpp`, `src/crypto.cpp`)
- `nvhttp.cpp`: GameStream-compatible HTTP API (client discovery, PIN pairing, app list)
- `rtsp.cpp`: RTSP handshake to negotiate stream parameters before streaming starts
- `crypto.cpp`: AES encryption for the control channel + certificate-based pairing

### Input (`src/input.cpp`)
- Receives input events from the client over the encrypted control channel
- Translates to OS input: `uinput`/`evdev` on Linux, SendInput on Windows
- Supports keyboard, mouse, touchpad, gamepads (up to 16 via `MAX_GAMEPADS`)

### Audio (`src/audio.cpp`)
- Captures system audio on the host
- Linux: PipeWire / PulseAudio; Windows: WASAPI

### Process / App Management (`src/process.cpp`)
- Launches the game/app when a client starts a session
- Reads `apps.json` for the app list
- Tracks the running process; ends the stream when the process exits

### Display Device (`src/display_device.cpp`)
- Manages display configuration (resolution, refresh rate, HDR) around streaming sessions
- Restores original settings after stream ends; persists state across crashes

### Config (`src/config.cpp`)
- Parses `sunshine.conf` and CLI arguments
- All tunable parameters: capture backend, encoder, bitrate, resolution, ports, etc.

---

## Platform Abstraction

`src/platform/common.h` defines the `platf::` namespace with abstract types:
- `display_t` — screen capture interface
- `mic_t` — audio capture
- `input_t` — virtual input device
- `deinit_t` — RAII guard for platform init/deinit

Each platform (`linux/`, `windows/`, `macos/`) provides concrete implementations. This is the boundary where most Linux-specific contributions live.

---

## Where Each TCC Idea Lives

| Idea | Primary files | Isolation |
|------|--------------|-----------|
| #2 — 10-bit portal fix | `platform/linux/portalgrab.cpp` | Single file, ~10 lines |
| #3 — Launcher bypass | `process.cpp`, `apps.json` format | Moderate; needs heuristic/registry |
| #4 — Dynamic quality | `stream.cpp` + `process.cpp` + env/API design | Cross-cutting |
| #5 — Virtual display | `platform/linux/` (new file) + `config.cpp` | New backend; moderate–large |
| #6 — Auto-detect apps | `process.cpp` + `nvhttp.cpp` + `apps.json` | Moderate |

---

## Related
- [[capture-backends]]
- [[nvfbc]]
- [[wayland-vs-x11]]

## Sources
- Sunshine source: `src/main.cpp`, `src/stream.cpp`, `src/video.cpp`, `src/platform/common.h`
- Sunshine source tree: `src/platform/linux/`
