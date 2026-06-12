"""Generate a poster-friendly timeline for Scenario A — 3 controllers.

Single figure, two panels (RTT + bitrate), large fonts, clean axes, x cut
where the action ends.

Output: poster_timeline_A.png (also into final_paper/poster/).
"""
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

HERE = Path(__file__).resolve().parent
RESULTS = HERE.parent.parent / 'results'

OUT_PATHS = [
    HERE / 'poster_timeline_A.png',
    HERE.parent.parent.parent / 'knowledge' / 'final_paper' / 'poster' / 'poster_timeline_A.png',
]

# ── Per-controller styling ──────────────────────────────────────────
CTRL = {
    'baseline': {
        'csv': sorted((RESULTS / 'baseline').glob('A_run0_*.csv'))[0],
        'label': 'sem ABR',
        'color': '#888888',
        'lw': 3.2,
    },
    'adaptive': {
        'csv': sorted((RESULTS / 'adaptive').glob('A_run0_*.csv'))[0],
        'label': 'AIMD de base',
        'color': '#1f77b4',
        'lw': 3.2,
    },
    'cubic': {
        'csv': sorted((RESULTS / 'cubic').glob('A_run0_*.csv'))[0],
        'label': 'MACCA',
        'color': '#d62728',
        'lw': 3.6,
    },
}

# Scenario A: 8 Mbps cap, 80--160 s
SHAPING_START = 80
SHAPING_END = 160
CAP_MBPS = 8.0

# Visible time window — cut dead time
T_VIS_MIN = 0
T_VIS_MAX = 220


# ── Load ────────────────────────────────────────────────────────────
data = {}
for k, info in CTRL.items():
    df = pd.read_csv(info['csv'])
    df['t_s'] = df['elapsed_ms'] / 1000.0
    # downsample for cleaner lines on the poster
    df = df[(df['t_s'] >= T_VIS_MIN) & (df['t_s'] <= T_VIS_MAX)]
    data[k] = df


# ── Canvas ──────────────────────────────────────────────────────────
fig, (ax_rtt, ax_bw) = plt.subplots(
    2, 1, figsize=(13, 7.5), sharex=True,
    gridspec_kw={'height_ratios': [1.0, 0.85]},
)

# ── Shaded shaping window on both axes ──────────────────────────────
for ax in (ax_rtt, ax_bw):
    ax.axvspan(SHAPING_START, SHAPING_END, alpha=0.13, color='#ffa726',
               zorder=0, label='_nolegend_')

# ── Top panel: RTT ──────────────────────────────────────────────────
for k, info in CTRL.items():
    df = data[k]
    ax_rtt.plot(df['t_s'], df['rtt_ms'],
                color=info['color'], linewidth=info['lw'],
                label=info['label'], alpha=0.92)

ax_rtt.axhline(100, color='#444', linestyle='--', linewidth=1.4, alpha=0.6)
ax_rtt.text(T_VIS_MAX - 2, 140, 'limiar de 100 ms',
            ha='right', fontsize=13, color='#444', style='italic')

ax_rtt.set_ylabel('RTT (ms)', fontsize=18, fontweight='bold')
ax_rtt.set_ylim(0, 2000)
ax_rtt.tick_params(axis='both', labelsize=14)
ax_rtt.grid(True, alpha=0.3)
ax_rtt.legend(loc='upper right', fontsize=15, framealpha=0.95,
              edgecolor='#444')

# Annotate the shaping window
ax_rtt.text((SHAPING_START + SHAPING_END) / 2, 1900,
            f'shaping: {CAP_MBPS:.0f} Mbps',
            ha='center', fontsize=14, color='#b56a00',
            fontweight='bold', style='italic')

# ── Bottom panel: bitrate target ────────────────────────────────────
for k, info in CTRL.items():
    df = data[k]
    bitrate_mbps = df['target_kbps'] / 1000.0
    ax_bw.plot(df['t_s'], bitrate_mbps,
               color=info['color'], linewidth=info['lw'],
               alpha=0.92)

# tc htb cap profile
t_cap = np.array([T_VIS_MIN, SHAPING_START, SHAPING_START,
                  SHAPING_END, SHAPING_END, T_VIS_MAX])
y_cap = np.array([25, 25, CAP_MBPS, CAP_MBPS, 25, 25])
ax_bw.plot(t_cap, y_cap, color='#666', linestyle=':', linewidth=2.2,
           label='cap da rede', zorder=1)

ax_bw.set_xlabel('tempo (s)', fontsize=18, fontweight='bold')
ax_bw.set_ylabel('taxa-alvo do\ncodificador (Mbps)', fontsize=17, fontweight='bold')
ax_bw.set_ylim(0, 22)
ax_bw.set_xlim(T_VIS_MIN, T_VIS_MAX)
ax_bw.tick_params(axis='both', labelsize=14)
ax_bw.grid(True, alpha=0.3)
ax_bw.legend(loc='upper right', fontsize=13, framealpha=0.95,
             edgecolor='#444')

# ── Titles / spacing ────────────────────────────────────────────────
fig.suptitle('Cenário A — queda abrupta para 8 Mbps em $t = 80$ s',
             fontsize=19, fontweight='bold', y=0.99)

plt.tight_layout(rect=[0, 0, 1, 0.97])

for out in OUT_PATHS:
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=180, bbox_inches='tight')
    print(f'wrote {out}')
plt.close(fig)
