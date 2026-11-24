#!/usr/bin/env bash
# lab-part-04 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p03"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3"
test -f "$D/04-respuesta.txt" || exit 1
$K -n metallb-system get deployment metallb-controller -o json 2>/dev/null | jq -e '(.spec.template.spec.containers[0].image | endswith(":v0.16.2")) and .status.readyReplicas==1' >/dev/null || exit 1
test "$(docker inspect -f '{{.State.Running}}' ckne-lab3-frontera 2>/dev/null)" = "true" || exit 1
FRONTERA=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' ckne-lab3-frontera)
$K -n metallb-system get ipaddresspool rango-lab -o json 2>/dev/null | jq -e '.spec.addresses==["198.51.100.10-198.51.100.20"]' >/dev/null || exit 1
$K -n metallb-system get bgppeer.v1beta2.metallb.io frontera -o json 2>/dev/null | jq -e --arg f "$FRONTERA" '.spec.myASN==64601 and .spec.peerASN==64600 and .spec.peerAddress==$f' >/dev/null || exit 1
$K -n metallb-system get bgpadvertisement -o json 2>/dev/null | jq -e '[.items[] | select((.spec.ipAddressPools // []) | index("rango-lab") != null)] | length >= 1' >/dev/null || exit 1
SVC=$($K -n envios get service vitrina -o json 2>/dev/null)
echo "$SVC" | jq -e '.spec.type=="LoadBalancer" and .spec.selector=={"app":"vitrina"} and .metadata.annotations["metallb.io/ip-allocated-from-pool"]=="rango-lab"' >/dev/null || exit 1
LB=$(echo "$SVC" | jq -r '.status.loadBalancer.ingress[0].ip // empty')
echo "$LB" | grep -qE '^198\.51\.100\.(1[0-9]|20)$' || exit 1
test "$($K -n envios get deployment vitrina -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" = "2" || exit 1
# La ruta se lee en la tabla del vecino: aprendida por BGP, elegida, y con los dos trabajadores.
WS=$($K get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' | sort | tr '\n' ' ')
RUTA=$(docker exec ckne-lab3-frontera vtysh -c "show ip route $LB/32 json" 2>/dev/null)
echo "$RUTA" | jq -e --arg p "$LB/32" '.[$p][0].protocol=="bgp" and .[$p][0].selected==true' >/dev/null || exit 1
test "$(echo "$RUTA" | jq -r --arg p "$LB/32" '[.[$p][0].nexthops[].ip] | sort | join(" ")') " = "$WS" || exit 1
test "$(docker exec ckne-lab3-frontera vtysh -c 'show running-config' 2>/dev/null | grep -c '^ip route ')" = "0" || exit 1
VIVOS=$($K -n envios get pods -l app=vitrina -o jsonpath='{.items[*].metadata.name}')
R=$(docker exec ckne-lab3-frontera wget -qO- -T5 "http://$LB/" 2>/dev/null | tr -d '\r\n')
test -n "$R" || exit 1
echo " $VIVOS " | grep -qF " $R " || exit 1
grep -qxF "IP_ANUNCIADA=$LB" "$D/04-respuesta.txt" || exit 1
grep -qxF "SALTOS_HACIA_LA_IP=2" "$D/04-respuesta.txt" || exit 1
grep -qxF "AS_DEL_CLUSTER=64601" "$D/04-respuesta.txt" || exit 1
echo ok
