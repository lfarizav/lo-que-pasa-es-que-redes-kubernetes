#!/usr/bin/env bash
# lab-part-03 step 2 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p02"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab2"
test -f "$D/02-respuesta.txt" || exit 1
test -f "$D/02-conntrack.txt" || exit 1
SVC=$($K -n cabina get service meteo-calle -o json 2>/dev/null)
test -n "$SVC" || exit 1
test "$(echo "$SVC" | jq -r '.spec.type')" = "NodePort" || exit 1
test "$(echo "$SVC" | jq -c '.spec.selector')" = '{"app":"meteo"}' || exit 1
test "$(echo "$SVC" | jq -r '.spec.ports[0].nodePort')" = "30380" || exit 1
$K -n cabina get pods -l app=meteo -o json | jq -e '[.items[] | select(.spec.hostNetwork==true or ([.spec.containers[].ports[]?.hostPort] | map(select(. != null)) | length > 0))] | length == 0' >/dev/null || exit 1
VIVOS=$($K -n cabina get pods -l app=meteo -o jsonpath='{.items[*].metadata.name}')
for N in ckne-lab2-worker ckne-lab2-worker2; do
  IP=$($K get node "$N" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
  R=$(curl -s -m5 "http://$IP:30380/" | tr -d '\r\n')
  test -n "$R" || exit 1
  echo " $VIVOS " | grep -qF " $R " || exit 1
done
MODO=$($K -n kube-system get configmap kube-proxy -o jsonpath='{.data.config\.conf}' | sed -n 's/^mode: *//p' | tr -d '"')
test -n "$MODO" || MODO=iptables
LISTOS=$($K -n cabina get endpointslice -l kubernetes.io/service-name=meteo -o json | jq '[.items[].endpoints[] | select(.conditions.ready==true)] | length')
CADENAS=$(docker exec ckne-lab2-worker iptables-save -t nat 2>/dev/null | grep -F '"cabina/meteo:http"' | grep -cF -- '-j DNAT')
test "$CADENAS" = "$LISTOS" || exit 1
MIP=$($K -n cabina get pods -l app=meteo -o jsonpath='{.items[*].status.podIP}')
ARCH=$(grep -E 'dport=30380 ' "$D/02-conntrack.txt" | grep -oE 'src=192\.168\.[0-9]+\.[0-9]+ dst=[0-9.]+ sport=8080 ' | sed 's/^src=//; s/ .*//' | sort -u)
test -n "$ARCH" || exit 1
VISTO=no
for P in $ARCH; do echo " $MIP " | grep -qF " $P " && VISTO=si; done
test "$VISTO" = "si" || exit 1
W1=$($K get node ckne-lab2-worker -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
curl -s -m5 -o /dev/null "http://$W1:30380/" || exit 1
VIVA=$(docker exec ckne-lab2-worker conntrack -L -p tcp --dport 30380 2>/dev/null | grep -E 'dport=30380 ' | grep -oE 'src=192\.168\.[0-9]+\.[0-9]+ dst=[0-9.]+ sport=8080 ' | head -1)
test -n "$VIVA" || exit 1
grep -qxF "MODO_DE_KUBE_PROXY=$MODO" "$D/02-respuesta.txt" || exit 1
grep -qxF "CADENAS_DE_EXTREMO=$CADENAS" "$D/02-respuesta.txt" || exit 1
grep -qxF "PUERTO_DE_NODO=30380" "$D/02-respuesta.txt" || exit 1
echo ok
