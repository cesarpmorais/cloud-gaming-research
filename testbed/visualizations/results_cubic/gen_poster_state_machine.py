"""Poster-friendly state machine for MACCA — academic register.

Output: poster_state_machine.png (also into final_paper/poster/).
"""
from pathlib import Path
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch

HERE = Path(__file__).resolve().parent
OUT_PATHS = [
    HERE / 'poster_state_machine.png',
    HERE.parent.parent.parent / 'knowledge' / 'final_paper' / 'poster' / 'poster_state_machine.png',
]

BLUE       = '#2f529e'
BLUE_FILL  = '#dde6f4'
RED        = '#c0392b'
RED_FILL   = '#fadbd6'
GREEN      = '#2c7a3d'
GREEN_FILL = '#d6ebd2'
EDGE_GREY  = '#555555'

fig, ax = plt.subplots(figsize=(13, 5))
ax.set_xlim(0, 14)
ax.set_ylim(0, 6.5)
ax.set_aspect('equal')
ax.axis('off')


def state_box(cx, cy, w, h, label, fill, border):
    box = FancyBboxPatch(
        (cx - w / 2, cy - h / 2), w, h,
        boxstyle='round,pad=0.04,rounding_size=0.25',
        linewidth=2.2, edgecolor=border, facecolor=fill,
    )
    ax.add_patch(box)
    ax.text(cx, cy, label, ha='center', va='center',
            fontsize=18, fontweight='bold', color=border)


# Top row — observation states
state_box(3.5,  5.2, 3.8, 1.1, 'ESTÁVEL',       BLUE_FILL, BLUE)
state_box(10.5, 5.2, 3.8, 1.1, 'CONGESTIONADO', RED_FILL,  RED)

# Bottom row — action states
state_box(3.5,  1.5, 3.8, 1.1, 'AUMENTA TAXA',  GREEN_FILL, GREEN)
state_box(10.5, 1.5, 3.8, 1.1, 'REDUZ TAXA',    RED_FILL,   RED)


def arrow(start, end, color, linewidth=2.2, rad=0.0):
    a = FancyArrowPatch(
        start, end, arrowstyle='->', mutation_scale=22,
        color=color, linewidth=linewidth,
        connectionstyle=f'arc3,rad={rad}',
    )
    ax.add_patch(a)


# Top: bidirectional between ESTÁVEL and CONGESTIONADO
arrow((5.5, 5.45), (8.55, 5.45), color=EDGE_GREY, linewidth=2.2)
arrow((8.55, 4.95), (5.5, 4.95), color=EDGE_GREY, linewidth=2.2)
ax.text(7.0, 5.95, 'RTT > 100 ms',
        ha='center', va='center', fontsize=13, color=EDGE_GREY, style='italic')
ax.text(7.0, 4.45, 'RTT < 80 ms',
        ha='center', va='center', fontsize=13, color=EDGE_GREY, style='italic')
ax.text(7.0, 3.55, 'margem de histerese: 20 ms',
        ha='center', va='center', fontsize=10, color='#888', style='italic')

# Down arrows: action transitions (shorter now)
arrow((3.5, 4.65), (3.5, 2.05), color=GREEN, linewidth=2.6)
arrow((10.5, 4.65), (10.5, 2.05), color=RED, linewidth=2.6)

# Labels on down arrows — sustained condition triggers the action
ax.text(3.5, 3.35, 'estabilidade\nsustentada',
        ha='center', va='center', fontsize=13, color=GREEN,
        fontweight='bold', style='italic',
        bbox=dict(boxstyle='round,pad=0.35', facecolor='white',
                  edgecolor='none', alpha=0.97))

ax.text(10.5, 3.35, 'congestão\nsustentada',
        ha='center', va='center', fontsize=13, color=RED,
        fontweight='bold', style='italic',
        bbox=dict(boxstyle='round,pad=0.35', facecolor='white',
                  edgecolor='none', alpha=0.97))

# Action descriptions below the bottom boxes
ax.text(3.5, 0.5, 'curva cúbica de recuperação',
        ha='center', va='center', fontsize=12, color=GREEN, style='italic')

ax.text(10.5, 0.5, r'decremento multiplicativo ($\beta = 0{,}7$)',
        ha='center', va='center', fontsize=12, color=RED, style='italic')

plt.tight_layout()
for out in OUT_PATHS:
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=160, bbox_inches='tight')
    print(f'wrote {out}')
plt.close(fig)
