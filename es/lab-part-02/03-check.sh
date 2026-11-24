#!/usr/bin/env bash
# lab-part-02 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p01"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab1"
test -f "$D/03-captura-eth0.txt" || exit 1
test -f "$D/03-captura-tunl0.txt" || exit 1
test -f "$D/03-respuesta.txt" || exit 1
IPB=$($K -n vecinos get pod vecino-b -o jsonpath='{.status.podIP}' 2>/dev/null)
IPA=$($K -n vecinos get pod vecino-a -o jsonpath='{.status.podIP}' 2>/dev/null)
test -n "$IPA" && test -n "$IPB" || exit 1
SRC=$($K get node ckne-lab1-worker -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
DST=$($K get node ckne-lab1-worker2 -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
test -n "$SRC" && test -n "$DST" || exit 1
N=$(grep -F "IP $SRC > $DST: IP $IPA." "$D/03-captura-eth0.txt" | grep -cF " > $IPB.8080:")
test "$N" -ge 2 || exit 1
grep -q 'listening on eth0' "$D/03-captura-eth0.txt" || exit 1
grep -q 'listening on tunl0' "$D/03-captura-tunl0.txt" || exit 1
grep -q '^0 packets captured' "$D/03-captura-tunl0.txt" || exit 1
grep -qxF "NODO_CON_FALLA=ckne-lab1-worker2" "$D/03-respuesta.txt" || exit 1
grep -qxF "PROTOCOLO_IP=4" "$D/03-respuesta.txt" || exit 1
grep -qxF "LLEGA_A_ETH0=si" "$D/03-respuesta.txt" || exit 1
grep -qxF "LLEGA_A_TUNL0=no" "$D/03-respuesta.txt" || exit 1
echo ok
