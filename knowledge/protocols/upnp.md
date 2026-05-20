# UPnP (Universal Plug and Play)

## What is it?
UPnP is a set of networking protocols that allows devices on a local network to automatically discover each other and configure network services — including opening ports on a router — without manual intervention.

For game streaming, the relevant part is **NAT traversal via UPnP**: Sunshine can ask your router to automatically forward the necessary ports to your machine, so Moonlight clients outside your LAN can reach it without you manually configuring port forwarding.

## Why it matters for Sunshine / TCC
Sunshine has built-in UPnP support (`src/upnp.cpp`, started in `main.cpp` as `upnp::start()`). When enabled, it automatically maps the required ports on your router at session start and unmaps them on shutdown.

This enables testing across different network environments (LAN, home WiFi, mobile data, internet) — critical for collecting baseline data across conditions (relevant to ideas #7, #8, #9).

Without UPnP or manual port forwarding, Sunshine only works on the local network.

## Key Concepts
- **NAT (Network Address Translation)**: routers give devices private IPs (192.168.x.x) and translate to a single public IP. External clients can't reach private IPs directly.
- **Port forwarding**: manually telling the router "traffic on port X goes to device Y"
- **UPnP IGD (Internet Gateway Device)**: the UPnP profile routers expose that allows automatic port mapping
- **Sunshine's required ports**:
  | Port | Protocol | Purpose |
  |------|----------|---------|
  | 47984 | TCP | HTTPS (pairing) |
  | 47989 | TCP | HTTP (GameStream API) |
  | 47990 | TCP | Web UI |
  | 48010 | TCP | RTSP |
  | 47998 | UDP | Video |
  | 47999 | UDP | Control |
  | 48000 | UDP | Audio |

## Related
- [[architecture]]

## Sources
- Sunshine source: `src/upnp.cpp`, `src/upnp.h`
- Sunshine `main.cpp`: `upnp::start()` called at startup
