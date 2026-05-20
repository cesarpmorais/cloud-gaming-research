#!/usr/bin/env bash
# Sweep de packet loss numa única sessão Moonlight.
# Roda 7 fases de 30s cada (incluindo clean inicial/final), salva:
#   - CSV de FEC do Sunshine (todo o histórico)
#   - log de fase (timestamp do início de cada fase)
#   - tc stats por fase (drops contados)
#
# Uso: ./testbed/sweep_loss.sh [run_id]
#
# Pré-requisitos:
#   1. Sunshine rodando
#   2. Moonlight conectado e streamando jogo com movimento
#   3. NÃO desconectar durante o sweep — uma sessão só
#   4. IFACE exportado (default eno1)

set -euo pipefail

IFACE="${IFACE:-eno1}"
RUN_ID="${1:-$(date +%H%M%S)}"
METRICS_DIR="$HOME/code/ufmg/tcc/data/metrics"
OUT_DIR="$HOME/code/ufmg/tcc/testbed/results/sweep"
PHASE_DURATION=30  # segundos por fase

# Fases: (label, loss_pct). 0 = sem tc, 999 = clean (apenas remove tc).
PHASES=(
    "clean0 999"
    "loss1  1"
    "loss2  2"
    "loss5  5"
    "loss10 10"
    "loss15 15"
    "clean1 999"
)

mkdir -p "$OUT_DIR"

LOG_FILE="$OUT_DIR/sweep_${RUN_ID}.log"
PHASE_FILE="$OUT_DIR/sweep_${RUN_ID}.phases.tsv"
TC_FILE="$OUT_DIR/sweep_${RUN_ID}.tc_stats.txt"

# --- captura CSVs pré-existentes pra identificar o novo ---
mapfile -t PRE_CSVS < <(find "$METRICS_DIR" -maxdepth 1 -name '*.csv' 2>/dev/null | sort)

# --- cleanup trap ---
cleanup() {
    echo "[cleanup] Removendo tc qdisc..." | tee -a "$LOG_FILE"
    sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# --- sanity ---
echo "================================================================" | tee "$LOG_FILE"
echo " Loss Sweep — run_id=$RUN_ID  iface=$IFACE" | tee -a "$LOG_FILE"
echo " Phases: ${#PHASES[@]} x ${PHASE_DURATION}s = $((${#PHASES[@]} * PHASE_DURATION))s total" | tee -a "$LOG_FILE"
echo " Phase log: $PHASE_FILE" | tee -a "$LOG_FILE"
echo "================================================================" | tee -a "$LOG_FILE"

cat <<EOF
PROTOCOL:
  1. Sunshine deve estar rodando
  2. Moonlight conectado, num jogo com movimento (não menu)
  3. NÃO desconecte durante o sweep — sessão única
  4. Mexa a câmera durante todo o sweep pra encoder ter conteúdo

Aperta ENTER pra começar (ou Ctrl-C pra abortar).
EOF
read -r

# Limpa tc residual
sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true

# Header do log de fases
printf "phase\tloss_pct\tstart_unix_ms\ttc_dropped_at_start\ttc_dropped_at_end\n" > "$PHASE_FILE"

START_TS_MS=$(($(date +%s%N) / 1000000))
echo "[start] sweep_start_unix_ms=$START_TS_MS" | tee -a "$LOG_FILE"

# Helper pra ler 'dropped' do qdisc (0 se não há qdisc)
read_dropped() {
    sudo tc -s qdisc show dev "$IFACE" 2>/dev/null \
        | awk '/dropped/ {for(i=1;i<=NF;i++) if($i=="dropped") print $(i+1)}' \
        | head -1 \
        | tr -d ','
}

for entry in "${PHASES[@]}"; do
    read -r LABEL PCT <<< "$entry"

    PHASE_START_MS=$(($(date +%s%N) / 1000000))

    if [ "$PCT" = "999" ]; then
        echo "[phase=$LABEL] clean (no tc)" | tee -a "$LOG_FILE"
        sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true
        DROP_START=0
    else
        DROP_BEFORE=$(read_dropped || echo 0)
        echo "[phase=$LABEL] apply loss ${PCT}%" | tee -a "$LOG_FILE"
        sudo tc qdisc replace dev "$IFACE" root netem loss "${PCT}%"
        sleep 0.5
        DROP_START=$(read_dropped || echo 0)
        echo "  drops at start: $DROP_START" | tee -a "$LOG_FILE"
    fi

    sleep "$PHASE_DURATION"

    if [ "$PCT" != "999" ]; then
        DROP_END=$(read_dropped || echo 0)
        echo "  drops at end: $DROP_END  (delta: $((DROP_END - DROP_START)))" | tee -a "$LOG_FILE"
    else
        DROP_END=0
    fi

    printf "%s\t%s\t%s\t%s\t%s\n" "$LABEL" "$PCT" "$PHASE_START_MS" "$DROP_START" "$DROP_END" >> "$PHASE_FILE"
done

# Snapshot final do tc
{
    echo "=== final tc qdisc state ==="
    sudo tc -s qdisc show dev "$IFACE" 2>/dev/null || echo "(no qdisc)"
} > "$TC_FILE"

# --- localiza o CSV novo ---
sleep 2  # dá tempo de qualquer report tardio chegar
mapfile -t POST_CSVS < <(find "$METRICS_DIR" -maxdepth 1 -name '*.csv' 2>/dev/null | sort)

NEW_CSV=""
for f in "${POST_CSVS[@]}"; do
    found=0
    for g in "${PRE_CSVS[@]}"; do
        [ "$f" = "$g" ] && { found=1; break; }
    done
    [ "$found" -eq 0 ] && { NEW_CSV="$f"; break; }
done

if [ -z "$NEW_CSV" ]; then
    echo "*** WARNING: nenhum CSV novo gerado no $METRICS_DIR" | tee -a "$LOG_FILE"
    echo "    Possíveis causas: nenhum FEC report recebido. Sessão não foi nova." | tee -a "$LOG_FILE"
    exit 0
fi

CSV_DEST="$OUT_DIR/sweep_${RUN_ID}.csv"
cp "$NEW_CSV" "$CSV_DEST"

EVENTS=$(($(wc -l < "$CSV_DEST") - 1))
echo "      csv saved: $CSV_DEST  ($EVENTS events)" | tee -a "$LOG_FILE"

# --- análise por fase ---
echo "" | tee -a "$LOG_FILE"
echo "=== events per phase ===" | tee -a "$LOG_FILE"
echo "phase | loss% | events | tc_dropped" | tee -a "$LOG_FILE"
echo "------|-------|--------|-----------" | tee -a "$LOG_FILE"

# Para cada fase, conta events no CSV cujo timestamp está dentro da janela
PHASE_LINES=()
while IFS= read -r line; do PHASE_LINES+=("$line"); done < "$PHASE_FILE"

NUM_PHASES=${#PHASES[@]}
for i in $(seq 0 $((NUM_PHASES - 1))); do
    LINE="${PHASE_LINES[$((i+1))]}"  # skip header
    LABEL=$(echo "$LINE" | cut -f1)
    PCT=$(echo "$LINE" | cut -f2)
    PHASE_START=$(echo "$LINE" | cut -f3)
    DROPS_START=$(echo "$LINE" | cut -f4)
    DROPS_END=$(echo "$LINE" | cut -f5)
    PHASE_DROPS=$((DROPS_END - DROPS_START))

    # next phase start (or +duration if last)
    NEXT_IDX=$((i+2))
    if [ "$NEXT_IDX" -le "$NUM_PHASES" ]; then
        PHASE_END=$(echo "${PHASE_LINES[$NEXT_IDX]}" | cut -f3)
    else
        PHASE_END=$((PHASE_START + PHASE_DURATION * 1000))
    fi

    EVT_COUNT=$(awk -F, -v s="$PHASE_START" -v e="$PHASE_END" 'NR>1 && $1>=s && $1<e' "$CSV_DEST" | wc -l)
    printf "%-6s | %5s | %6d | %10d\n" "$LABEL" "$PCT" "$EVT_COUNT" "$PHASE_DROPS" | tee -a "$LOG_FILE"
done

echo "" | tee -a "$LOG_FILE"
echo "=== files ===" | tee -a "$LOG_FILE"
echo "csv:    $CSV_DEST" | tee -a "$LOG_FILE"
echo "phases: $PHASE_FILE" | tee -a "$LOG_FILE"
echo "tc:     $TC_FILE" | tee -a "$LOG_FILE"
echo "log:    $LOG_FILE" | tee -a "$LOG_FILE"
