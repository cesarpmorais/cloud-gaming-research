"""Generate the AIMD CUBIC controller state-machine diagram.

Output: state_machine.png (also into final_paper/images/).
"""
from pathlib import Path
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = Path(__file__).resolve().parent
OUT_PATHS = [
    HERE / 'state_machine.png',
    HERE.parent.parent.parent / 'knowledge' / 'final_paper' / 'images' / 'state_machine.png',
]

# ── Palette ──────────────────────────────────────────────────────────
LIVE_FILL    = '#dde9f5'
DEC_FILL     = '#f7d4d4'
PROBE_FILL   = '#d6ebd2'
EDGE         = '#1a1a1a'
SAMPLE_COLOR = '#404040'
DECIDE_COLOR = '#1f4d8a'

# ── Canvas ───────────────────────────────────────────────────────────
fig, ax = plt.subplots(figsize=(8.5, 4.6))
ax.set_xlim(0, 17)
ax.set_ylim(0, 9.2)
ax.set_aspect('equal')
ax.axis('off')


# ── State boxes ──────────────────────────────────────────────────────
def state_box(cx, cy, w, h, label, fill):
    box = FancyBboxPatch(
        (cx - w / 2, cy - h / 2), w, h,
        boxstyle='round,pad=0.03,rounding_size=0.22',
        linewidth=1.4, edgecolor=EDGE, facecolor=fill,
    )
    ax.add_patch(box)
    ax.text(cx, cy, label, ha='center', va='center',
            fontsize=11.5, weight='bold')


# Top row: live RTT-driven states
state_box(4.0, 7.2, 3.0, 1.1, 'estável',       LIVE_FILL)
state_box(13.0, 7.2, 3.4, 1.1, 'congestionado', LIVE_FILL)

# Bottom row: decision outcomes
state_box(2.0, 1.8, 2.8, 1.1, 'recuperando', PROBE_FILL)
state_box(6.0, 1.8, 2.8, 1.1, 'sondando',    PROBE_FILL)
state_box(13.0, 1.8, 2.8, 1.1, 'decrescendo', DEC_FILL)


# ── Arrow helper ────────────────────────────────────────────────────
def arrow(start, end, color=EDGE, rad=0.0,
          linewidth=1.4, linestyle='-'):
    a = FancyArrowPatch(
        start, end,
        arrowstyle='->', mutation_scale=16,
        color=color, linewidth=linewidth, linestyle=linestyle,
        connectionstyle=f'arc3,rad={rad}',
    )
    ax.add_patch(a)


# ── Per-sample (60 Hz) — two parallel horizontal arrows ─────────────
# Upper arrow: estável → congestionado, labelled above
arrow((5.55, 7.45), (11.28, 7.45), color=SAMPLE_COLOR)
ax.text(8.4, 7.85, r'RTT $>$ $\tau_{\rm cong}$',
        ha='center', va='center', fontsize=10,
        color=SAMPLE_COLOR, style='italic')

# Lower arrow: congestionado → estável, labelled below
arrow((11.28, 6.95), (5.55, 6.95), color=SAMPLE_COLOR)
ax.text(8.4, 6.55, r'RTT $\leq$ $\tau_{\rm cong} - m$',
        ha='center', va='center', fontsize=10,
        color=SAMPLE_COLOR, style='italic')

# ── 1 Hz decision transitions ───────────────────────────────────────
# estável → recuperando (diagonal down-left)
arrow((3.4, 6.6), (2.3, 2.4), color=DECIDE_COLOR)
ax.text(2.05, 4.5, r'$B(t) < L$',
        ha='right', va='center', fontsize=10,
        color=DECIDE_COLOR, style='italic')

# estável → sondando (diagonal down-right)
arrow((4.6, 6.6), (5.7, 2.4), color=DECIDE_COLOR)
ax.text(5.95, 4.5, r'$B(t) \geq L$',
        ha='left', va='center', fontsize=10,
        color=DECIDE_COLOR, style='italic')

# congestionado → decrescendo (straight down)
arrow((13.0, 6.6), (13.0, 2.4), color=DECIDE_COLOR)

# Annotation: "1 Hz" label as the trigger for the down-arrows
ax.text(4.0, 5.4, '1 Hz',
        ha='center', va='center', fontsize=10,
        color=DECIDE_COLOR, weight='bold')
ax.text(13.5, 4.5, '1 Hz',
        ha='left', va='center', fontsize=10,
        color=DECIDE_COLOR, weight='bold')

# ── Caption-style footnote ──────────────────────────────────────────
ax.text(
    8.5, 0.35,
    'Setas cinzas: avaliação por amostra (~60 Hz).  '
    'Setas azuis: decisão a 1 Hz.  '
    'Os rótulos da fila inferior persistem por um ciclo.',
    ha='center', va='center', fontsize=8.5, color='#555555', style='italic',
)

plt.tight_layout()
for out in OUT_PATHS:
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=160, bbox_inches='tight')
    print(f'wrote {out}')
plt.close(fig)
