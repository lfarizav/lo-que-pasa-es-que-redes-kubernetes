#!/usr/bin/env bash
# lab-part-05 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p04"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-cifra"
NS=nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70
test -f "$D/03-respuesta.txt" || exit 1
kind get clusters 2>/dev/null | grep -qx ckne-lab5-cifra || exit 1
NODOS=$($K get nodes -o json 2>/dev/null)
test "$(echo "$NODOS" | jq '.items | length')" -eq 3 || exit 1
echo "$NODOS" | jq -e '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length == 3' >/dev/null || exit 1
IMG=$($K -n kube-system get daemonset cilium -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
case "$IMG" in *:v1.20.5*) ;; *) exit 1 ;; esac
test "$($K -n kube-system get daemonset cilium -o jsonpath='{.status.numberReady}' 2>/dev/null)" = "3" || exit 1
# Los dos Pods de la prueba tienen que estar en nodos distintos: el trafico dentro de un nodo no cruza ninguna red.
test "$($K -n faro get pod origen -o jsonpath='{.spec.nodeName}' 2>/dev/null)" = "ckne-lab5-cifra-worker" || exit 1
DN=$($K -n faro get pod destino -o jsonpath='{.spec.nodeName}' 2>/dev/null)
test "$DN" = "ckne-lab5-cifra-worker2" || exit 1
test "$($K -n faro get pod destino -o jsonpath='{.spec.hostNetwork}' 2>/dev/null)" != "true" || exit 1
test "$($K -n faro get pod puente -o jsonpath='{.spec.hostNetwork}' 2>/dev/null)" = "true" || exit 1
for p in origen destino puente; do
  test "$($K -n faro get pod $p -o jsonpath='{.status.phase}' 2>/dev/null)" = "Running" || exit 1
done
# Cada agente tiene que decir Wireguard, no solo el que se miro.
N=0
for n in control-plane worker worker2; do
  P=$($K -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=ckne-lab5-cifra-$n -o name 2>/dev/null)
  test -n "$P" || exit 1
  $K -n kube-system exec $P -c cilium-agent -- cilium-dbg status 2>/dev/null | grep -qE '^Encryption: +Wireguard' && N=$((N+1))
done
test "$N" = "3" || exit 1
captura() { # origen destino -> imprime "legible udp"
  local T="ficha-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')" IP
  IP=$($K -n faro get pod "$2" -o jsonpath='{.status.podIP}')
  rm -f "$D/cap-grader.pcap"
  docker run -d --rm --name mirador-grader -v "$D":/c --network container:ckne-lab5-cifra-worker $NS tcpdump -i eth0 -nn -U -w /c/cap-grader.pcap >/dev/null 2>&1 || return 1
  sleep 3
  if [[ $1 == ckne-lab5-cifra-* ]]; then docker exec "$1" curl -s -m 3 -o /dev/null -H "Ficha:$T" "http://$IP/" >/dev/null 2>&1
  else $K -n faro exec "$1" -- curl -s -m 3 -o /dev/null -H "Ficha:$T" "http://$IP/" >/dev/null 2>&1; fi
  sleep 2; docker stop mirador-grader >/dev/null 2>&1
  local L U
  L=$(docker run --rm -v "$D":/c $NS tcpdump -r /c/cap-grader.pcap -nn -A 2>/dev/null | grep -c "$T")
  U=$(docker run --rm -v "$D":/c $NS tcpdump -r /c/cap-grader.pcap -nn udp port 51871 2>/dev/null | wc -l)
  rm -f "$D/cap-grader.pcap"
  echo "$L $U"
}
set -- $(captura origen destino)
test "$1" = "0" || exit 1
test "${2:-0}" -gt 0 || exit 1
PL=$(captura ckne-lab5-cifra-worker puente | cut -d' ' -f1)
test -n "$PL" || exit 1
grep -qxF "AGENTES_CON_WIREGUARD=3" "$D/03-respuesta.txt" || exit 1
grep -qxF "FICHA_LEGIBLE_ENTRE_PODS=0" "$D/03-respuesta.txt" || exit 1
grep -qxF "UDP_51871_ENTRE_PODS=si" "$D/03-respuesta.txt" || exit 1
grep -qxF "FICHA_LEGIBLE_HACIA_EL_PUENTE=$PL" "$D/03-respuesta.txt" || exit 1
echo ok
