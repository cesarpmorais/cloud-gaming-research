# Idea: NVFBC Benchmark on Consumer GPU

Status: 💡 raw

## Description
Test NVFBC on the RTX 4070 Super via nvfbc-unlock and benchmark it against KMS capture. Measure latency, CPU overhead, and frame consistency.

## Why it matters for TCC
Provides empirical data comparing capture backends — useful research content for the thesis even if not a direct PR contribution. Also directly relevant to headless streaming: NVFBC captures inside the GPU before display output, meaning it works without any monitor connected.

## Related Ideas
- [[idea-05-virtual-display]]

## Related Knowledge
- [[nvfbc]]
- [[capture-backends]]
