#!/usr/bin/env bash
# Confirma que o tc no $IFACE realmente afeta tráfego Sunshine -> Moonlight.
# Roda enquanto você está streamando: aplica 50% loss por 10s, mostra:
#   - rota/interface usada pra alcançar o Moonlight
#   - contador de drops do tc antes/depois
#   - rate de pacotes saindo
# Se o "dropped" não subir, o tc está no lugar errado.

set -euo pipefail

IFACE="${IFACE:-eno1}"

echo "================================================================"
echo " Path diagnostic — tc loss verification"
echo " Interface: $IFACE"
echo "================================================================"

read -rp "Cole aqui o IP do dispositivo Moonlight (ex: 192.168.15.x): " MOON_IP

if [ -z "$MOON_IP" ]; then
    echo "ERRO: IP vazio." >&2
    exit 1
fi

echo
echo "[1/5] Rota pra $MOON_IP:"
ip route get "$MOON_IP" || { echo "Sem rota."; exit 1; }

ACTUAL_IFACE=$(ip route get "$MOON_IP" | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
echo "      -> tráfego vai sair por: $ACTUAL_IFACE"
if [ "$ACTUAL_IFACE" != "$IFACE" ]; then
    echo "      *** ALERTA *** tc está em $IFACE mas tráfego sai por $ACTUAL_IFACE"
    echo "      Corrija com: export IFACE=$ACTUAL_IFACE"
fi

echo
echo "[2/5] Limpando tc residual em $IFACE..."
sudo tc qdisc del dev "$IFACE" root 2>/dev/null || true

echo
echo "[3/5] Snapshot de pacotes (antes do loss)..."
RX_BEFORE=$(cat /sys/class/net/"$IFACE"/statistics/tx_packets)
sleep 2
RX_AFTER=$(cat /sys/class/net/"$IFACE"/statistics/tx_packets)
PRE_PPS=$(( (RX_AFTER - RX_BEFORE) / 2 ))
echo "      tx_packets/s antes do loss: ~$PRE_PPS"

echo
echo "[4/5] Aplicando netem loss 50% por 10s..."
echo "      (Sunshine deve estar streamando. Olhe a tela do Moonlight pra ver se trava.)"
sudo tc qdisc replace dev "$IFACE" root netem loss 50%

sleep 10

echo
echo "[5/5] Stats do qdisc:"
sudo tc -s qdisc show dev "$IFACE"

echo
echo "Limpando tc..."
sudo tc qdisc del dev "$IFACE" root || true

echo
echo "================================================================"
echo " Análise:"
echo "   - Procure a linha 'dropped' nas stats do qdisc"
echo "   - Se dropped == 0: tc não dropou nada (interface errada?)"
echo "   - Se dropped grande: tc funcionou. Confirme se Moonlight"
echo "     mostrou stutter/artefatos durante os 10s."
echo "================================================================"
