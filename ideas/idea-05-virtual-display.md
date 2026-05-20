# Idea: Virtual Display / Headless Streaming

Status: 💡 raw

## Description
Allow Sunshine to stream without a physical monitor connected — screen can be off or the user can be doing something else on the PC. Apollo (the Sunshine fork) already implements this. The goal is to upstream a clean implementation into Sunshine itself.

Two paths to headless streaming:
- **NVFBC on NVIDIA**: captures inside the GPU before display output — no virtual display needed at all
- **Software virtual display**: tricks the OS into thinking a monitor is connected; universal fallback for all GPUs (Apollo's approach)

## Why it matters for TCC
One of the most-requested Sunshine features. Apollo proving it works makes upstreaming a realistic goal. Strong PR candidate with clear user impact. Connects to NVFBC research as an alternative implementation path.

## Related Ideas
- [[idea-01-nvfbc-benchmark]]
- [[idea-02-10bit-portal]]
- [[idea-04-dynamic-quality]]

## Related Knowledge
- [[nvfbc]]
- [[capture-backends]]
- [[wayland-vs-x11]]
