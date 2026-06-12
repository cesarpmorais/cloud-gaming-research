"""Generate the cubic recovery curve illustration B(t) for K=5s and K=15s.

Output: cubic_curve.png (also into final_paper/images/).
"""
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent
OUT_PATHS = [
    HERE / 'cubic_curve.png',
    HERE.parent.parent.parent / 'knowledge' / 'final_paper' / 'images' / 'cubic_curve.png',
]

BETA = 0.7
L = 10_000  # kbps — last_known_good ceiling


def B(t, K):
    C = (1 - BETA) * L / K ** 3
    return C * (t - K) ** 3 + L


fig, ax = plt.subplots(figsize=(6.4, 4.0))

t_max = 25.0
t = np.linspace(0, t_max, 500)

# Two K values
for K, color, label in [(5.0, '#1f77b4', '$K = 5$ s'),
                         (15.0, '#d62728', '$K = 15$ s')]:
    y = B(t, K)
    ax.plot(t, y, color=color, linewidth=2.0, label=label)
    # Mark K on x-axis
    ax.axvline(K, color=color, linestyle=':', linewidth=0.9, alpha=0.55)
    ax.text(K + 0.15, 1100, f'$t = K = {int(K)}$ s',
            color=color, fontsize=9, style='italic')

# Reference lines
ax.axhline(L, color='#444444', linestyle='--', linewidth=0.9, alpha=0.7)
ax.text(t_max - 0.3, L + 600, '$L$ (teto de recuperação)',
        color='#444444', fontsize=9.5, ha='right', style='italic')

# Mark beta*L as the starting point at t=0
beta_L = BETA * L
ax.axhline(beta_L, color='#888888', linestyle=':', linewidth=0.8, alpha=0.7)
ax.text(t_max - 0.3, beta_L - 850, r'$\beta \cdot L$ (taxa após decremento)',
        color='#888888', fontsize=9, ha='right', style='italic')

# Annotate the three regions for K=15 (the curve used in the campaign)
ax.annotate('', xy=(13.5, 4500), xytext=(2.0, 4500),
            arrowprops=dict(arrowstyle='<->', color='#666', lw=0.8))
ax.text(7.75, 5050, 'região côncava ($t < K$)',
        ha='center', fontsize=8.5, color='#444', style='italic')

ax.annotate('', xy=(t_max - 1.0, 15500), xytext=(15.5, 15500),
            arrowprops=dict(arrowstyle='<->', color='#666', lw=0.8))
ax.text((15.5 + t_max - 1.0) / 2, 16100, 'região convexa ($t > K$)',
        ha='center', fontsize=8.5, color='#444', style='italic')

# Styling
ax.set_xlabel('tempo desde a última redução $t$ (s)', fontsize=11)
ax.set_ylabel('$B(t)$ (kbps)', fontsize=11)
ax.set_xlim(0, t_max)
ax.set_ylim(0, 21000)
ax.set_yticks([0, 5000, 7000, 10000, 15000, 20000])
ax.grid(True, alpha=0.3)
ax.legend(loc='lower right', fontsize=10, framealpha=0.95)

plt.tight_layout()
for out in OUT_PATHS:
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=160, bbox_inches='tight')
    print(f'wrote {out}')
plt.close(fig)
