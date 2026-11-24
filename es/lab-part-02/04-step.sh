#!/usr/bin/env bash
# lab-part-02 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p01
K="kubectl --kubeconfig $HOME/ckne-lab/p01/kubeconfig --context kind-ckne-lab1"

docker exec ckne-lab1-worker2 iptables -t raw -S PREROUTING
docker exec ckne-lab1-worker2 iptables -t raw -D PREROUTING -p ipencap -j DROP
docker exec ckne-lab1-worker2 iptables -t raw -S PREROUTING

IPA=$($K -n vecinos get pod vecino-a -o jsonpath='{.status.podIP}')
IPB=$($K -n vecinos get pod vecino-b -o jsonpath='{.status.podIP}')

( docker exec ckne-lab1-worker2 timeout 10 tcpdump -nn -i tunl0 > 04-captura-tunl0.txt 2>&1 ) &
sleep 3
$K -n vecinos exec vecino-a -- wget -qO- -T5 http://$IPB:8080/
wait
cat 04-captura-tunl0.txt

$K get ippools.crd.projectcalico.org -o jsonpath='{.items[0].spec.ipipMode}{"\n"}'

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p01"
cat > "$D/04-respuesta.txt" <<RESP
TABLA_DE_LA_REGLA=raw
CADENA_DE_LA_REGLA=PREROUTING
MODO_IPIP_INTACTO=$($K get ippools.crd.projectcalico.org -o jsonpath='{.items[0].spec.ipipMode}')
RESP
cat "$D/04-respuesta.txt"
