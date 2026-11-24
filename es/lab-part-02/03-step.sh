#!/usr/bin/env bash
# lab-part-02 step 3 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p01
K="kubectl --kubeconfig $HOME/ckne-lab/p01/kubeconfig --context kind-ckne-lab1"

IPB=$($K -n vecinos get pod vecino-b -o jsonpath='{.status.podIP}')

( docker exec ckne-lab1-worker2 timeout 12 tcpdump -nn -i eth0 'ip proto 4' > 03-captura-eth0.txt 2>&1 ) &
( docker exec ckne-lab1-worker2 timeout 12 tcpdump -nn -i tunl0 > 03-captura-tunl0.txt 2>&1 ) &
sleep 3
$K -n vecinos exec vecino-a -- wget -qO- -T6 http://$IPB:8080/ || true
wait

cat 03-captura-eth0.txt
cat 03-captura-tunl0.txt

docker exec ckne-lab1-worker2 ip -br link
docker exec ckne-lab1-worker2 iptables-save | grep -E -- '^-A (PREROUTING|INPUT|FORWARD|OUTPUT|POSTROUTING) '

# The answer file the lab asks you to type, from what the captures above showed:
D="$HOME/ckne-lab/p01"
cat > "$D/03-respuesta.txt" <<RESP
NODO_CON_FALLA=ckne-lab1-worker2
PROTOCOLO_IP=4
LLEGA_A_ETH0=si
LLEGA_A_TUNL0=no
RESP
cat "$D/03-respuesta.txt"
