"""Generate the two missing thesis charts:

  1. tradeoff_scatter.png  --  peak RTT vs p50 RTT (the "complementary
     priorities" trade-off in one image).
  2. rtt_cdf_panel.png     --  empirical CDF of RTT per controller,
     one subplot per scenario; visualises tail vs steady-state.

Run from this directory:  python gen_thesis_charts.py
Outputs land alongside this file.
"""
from pathlib import Path
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# ── Setup ────────────────────────────────────────────────────────────
HERE = Path(__file__).resolve().parent
RESULTS_DIR = HERE.parent.parent / 'results'
DIRS = {
    'baseline': RESULTS_DIR / 'baseline',
    'adaptive': RESULTS_DIR / 'adaptive',
    'cubic':    RESULTS_DIR / 'cubic',
}
SCENARIOS = ['A', 'B', 'C', 'D', 'E', 'F']

COLOR = {'baseline': '#888888', 'adaptive': '#1f77b4', 'cubic': '#d62728'}
LABEL = {'baseline': 'sem ABR', 'adaptive': 'AIMD de base', 'cubic': 'AIMD CUBIC'}
MARKER = {'A': 'o', 'B': 's', 'C': '^', 'D': 'D', 'E': 'P', 'F': 'X'}

# ── Load ─────────────────────────────────────────────────────────────
def find_run(directory, scenario):
    csvs = sorted(directory.glob(f'{scenario}_run0_*.csv'))
    return csvs[0] if csvs else None

def load_rtt(mode, scenario):
    p = find_run(DIRS[mode], scenario)
    if p is None:
        return None
    return pd.read_csv(p)['rtt_ms'].values

data = {m: {s: load_rtt(m, s) for s in SCENARIOS} for m in DIRS}

# ── Chart 1: Trade-off scatter (peak vs p50) ─────────────────────────
def make_tradeoff_scatter():
    fig, ax = plt.subplots(figsize=(7, 5))
    for m in DIRS:
        for s in SCENARIOS:
            rtt = data[m][s]
            if rtt is None:
                continue
            ax.scatter(
                np.median(rtt), rtt.max(),
                marker=MARKER[s], color=COLOR[m],
                s=110, edgecolors='black', linewidths=0.6, alpha=0.9,
            )
    # Legend: two columns — controllers + scenarios
    ctrl_handles = [plt.Line2D([0], [0], marker='o', linestyle='', markersize=9,
                               color=COLOR[m], markeredgecolor='black',
                               label=LABEL[m]) for m in DIRS]
    scen_handles = [plt.Line2D([0], [0], marker=MARKER[s], linestyle='', markersize=9,
                               color='#444444', markeredgecolor='black',
                               label=f'cenário {s}') for s in SCENARIOS]
    leg1 = ax.legend(handles=ctrl_handles, loc='upper left', fontsize=9,
                     title='controlador', title_fontsize=9, framealpha=0.95)
    ax.add_artist(leg1)
    ax.legend(handles=scen_handles, loc='lower right', fontsize=8,
              title='cenário', title_fontsize=9, ncol=2, framealpha=0.95)

    ax.set_xscale('log')
    ax.set_yscale('log')
    ax.set_xlabel('p50 RTT (ms) — regime estacionário', fontsize=11)
    ax.set_ylabel('pico RTT (ms) — cauda', fontsize=11)
    ax.set_title('Trade-off cauda × regime estacionário\n'
                 '(canto inferior-esquerdo = melhor em ambos)',
                 fontsize=11)
    ax.grid(True, which='major', alpha=0.3)
    ax.grid(True, which='minor', alpha=0.1)

    plt.tight_layout()
    out = HERE / 'tradeoff_scatter.png'
    fig.savefig(out, dpi=150, bbox_inches='tight')
    print(f'wrote {out}')
    plt.close(fig)

# ── Chart 2: RTT CDF panel ───────────────────────────────────────────
def make_cdf_panel():
    fig, axes = plt.subplots(2, 3, figsize=(11, 6.5), sharey=True)
    axes = axes.flatten()

    # Compute global x-limit per scenario to keep panels comparable.
    # Use log scale so adaptive/CUBIC distinction in low range stays visible.
    for i, s in enumerate(SCENARIOS):
        ax = axes[i]
        for m in DIRS:
            rtt = data[m][s]
            if rtt is None:
                continue
            sorted_rtt = np.sort(rtt)
            cdf = np.arange(1, len(sorted_rtt) + 1) / len(sorted_rtt)
            ax.plot(sorted_rtt, cdf, color=COLOR[m], label=LABEL[m],
                    linewidth=1.5)
        ax.axvline(100, color='black', linestyle=':', linewidth=0.8, alpha=0.6)
        ax.set_xscale('log')
        ax.set_xlim(1, 10000)
        ax.set_ylim(0, 1.02)
        ax.set_title(f'cenário {s}', fontsize=11)
        ax.grid(True, alpha=0.3)
        if i % 3 == 0:
            ax.set_ylabel('CDF', fontsize=10)
        if i >= 3:
            ax.set_xlabel('RTT (ms)', fontsize=10)

    # Shared legend at top
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc='upper center', ncol=3,
               bbox_to_anchor=(0.5, 1.02), fontsize=10, framealpha=0.95)

    fig.suptitle(
        'Distribuição cumulativa empírica de RTT por cenário\n'
        '(linha pontilhada: limiar de 100 ms)',
        fontsize=11, y=1.06,
    )
    plt.tight_layout()
    out = HERE / 'rtt_cdf_panel.png'
    fig.savefig(out, dpi=150, bbox_inches='tight')
    print(f'wrote {out}')
    plt.close(fig)

if __name__ == '__main__':
    make_tradeoff_scatter()
    make_cdf_panel()
