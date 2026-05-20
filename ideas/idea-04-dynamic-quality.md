# Idea: Dynamic Graphics Quality Based on Streaming FPS Target

Status: 💡 raw

## Description
When streaming at 30fps, the game has 33ms per frame instead of 16ms. That extra headroom could be used to automatically raise graphical fidelity settings (shadows, draw distance, etc.) since the GPU isn't racing to hit 60fps. Sunshine would need to communicate the target FPS to the host system or game, which could then adjust its settings accordingly.

## Why it matters for TCC
Novel idea with real user impact — streaming at 30fps currently just means lower smoothness with no quality compensation. Would require Sunshine-side changes to expose stream parameters to the host environment, plus either game-specific integrations or a generic API.

## Related Ideas
- [[idea-03-launcher-bypass]]
- [[idea-05-virtual-display]]

## Related Knowledge
- [[capture-backends]]
