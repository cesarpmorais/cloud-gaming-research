"""Poster-friendly scenario strip — just the cap profile per scenario.

Output: poster_scenarios.png (also into final_paper/poster/).
"""
from pathlib import Path
import matplotlib.pyplot as plt

HERE = Path(__file__).resolve().parent
OUT_PATHS = [
    HERE / 'poster_scenarios.png',
    HERE.parent.parent.parent / 'knowledge' / 'final_paper' / 'poster' / 'poster_scenarios.png',
]

SCENARIOS = {
    'A': [(80, 160, 8)],
    'B': [(60, 90, 16), (90, 120, 12), (120, 160, 8)],
    'C': [(40, 120, 14), (120, 200, 10)],
    'D': [(30, 60, 10), (90, 120, 10), (150, 180, 10), (210, 240, 10)],
    'E': [(40, 200, 4)],
    'F': [(0, 160, 6)],
}

CHANNEL_NATIVE = 22
T_MAX = 240
Y_MAX = 25

LINE_COLOR = '#2f529e'
FILL_COLOR = '#dde6f4'
AXIS_COLOR = '#666666'


def cap_trajectory(shape, t_max=T_MAX, native=CHANNEL_NATIVE):
    """Build a step trajectory of the cap profile, collapsing back-to-back
    windows so we don't draw spurious vertical segments at the seam."""
    pts = [(0, native)]
    current = native
    i = 0
    while i < len(shape):
        t_start, t_end, cap = shape[i]
        # If we're at native and a window starts, drop down
        if current != cap:
            pts.append((t_start, current))  # hold current until t_start
            pts.append((t_start, cap))      # drop to cap
            current = cap
        else:
            pts.append((t_start, current))
        # Hold cap until t_end
        pts.append((t_end, cap))
        # Look ahead: does the next window start exactly at t_end?
        if i + 1 < len(shape) and shape[i + 1][0] == t_end:
            next_cap = shape[i + 1][2]
            # Step directly to the next cap, no rise to native
            pts.append((t_end, next_cap))
            current = next_cap
        else:
            # Rise back to native
            pts.append((t_end, native))
            current = native
        i += 1
    pts.append((t_max, native))
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return xs, ys


# ── Canvas ──────────────────────────────────────────────────────────
fig, axes = plt.subplots(1, 6, figsize=(18, 3.4), sharey=True)

for i, (ax, (letter, shape)) in enumerate(zip(axes, SCENARIOS.items())):
    xs, ys = cap_trajectory(shape)

    ax.fill_between(xs, 0, ys, color=FILL_COLOR, zorder=1)
    ax.plot(xs, ys, color=LINE_COLOR, linewidth=2.8, zorder=2)

    # Letter on top
    ax.set_title(letter, fontsize=40, fontweight='bold',
                 color=LINE_COLOR, pad=6)

    ax.set_ylim(0, Y_MAX)
    ax.set_xlim(0, T_MAX)

    # Minimal x-axis: just the time label
    ax.set_xticks([0, T_MAX])
    ax.set_xticklabels(['0', f'{T_MAX} s'], fontsize=11, color=AXIS_COLOR)
    ax.set_xlabel('tempo', fontsize=12, color=AXIS_COLOR)

    # y-axis only on the leftmost subplot
    if i == 0:
        ax.set_yticks([0, CHANNEL_NATIVE])
        ax.set_yticklabels(['0', f'{CHANNEL_NATIVE}'], fontsize=11,
                           color=AXIS_COLOR)
        ax.set_ylabel('banda (Mbps)', fontsize=12, color=AXIS_COLOR)
    else:
        ax.set_yticks([])

    # Subtle axes — only bottom and left
    for spine in ['top', 'right']:
        ax.spines[spine].set_visible(False)
    for spine in ['bottom', 'left']:
        ax.spines[spine].set_color(AXIS_COLOR)
        ax.spines[spine].set_linewidth(0.8)
    if i != 0:
        ax.spines['left'].set_visible(False)
    ax.tick_params(colors=AXIS_COLOR, length=3)

plt.tight_layout()
for out in OUT_PATHS:
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=180, bbox_inches='tight')
    print(f'wrote {out}')
plt.close(fig)
