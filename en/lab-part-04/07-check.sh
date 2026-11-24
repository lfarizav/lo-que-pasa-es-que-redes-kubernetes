#!/usr/bin/env bash
# lab-part-04 step 7 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p03"
K1="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-uno"
K2="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-dos"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/ficha-de-la-consigna.txt" || exit 1
FICHA=$(tr -d '\r\n' < "$D/ficha-de-la-consigna.txt")
test -n "$FICHA" || exit 1
test "$(printf %s "$FICHA" | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.ficha.sha256")" || exit 1
# En dos: una Service ClusterIP con selector y un Pod listo de resguardo detras, exportada.
PSVC=$($K2 -n resguardo get service consigna -o json 2>/dev/null)
test -n "$PSVC" || exit 1
echo "$PSVC" | jq -e '.spec.type=="ClusterIP" and ((.spec.clusterIP // "None") != "None") and ((.spec.selector // {}) | length > 0) and any(.spec.ports[]; .port==80)' >/dev/null || exit 1
SEL=$(echo "$PSVC" | jq -r '.spec.selector | to_entries | map("\(.key)=\(.value)") | join(",")')
PODS=$($K2 -n resguardo get pods -l "$SEL" -o json 2>/dev/null | jq -c '[.items[] | select(.status.phase=="Running") | {n: .metadata.name, ip: .status.podIP}]')
test -n "$PODS" && test "$PODS" != "[]" || exit 1
LISTOS=$($K2 -n resguardo get endpointslice -l kubernetes.io/service-name=consigna -o json 2>/dev/null | jq -c --argjson p "$PODS" '[.items[].endpoints[]? | select(.conditions.ready==true and .targetRef.kind=="Pod" and ((.targetRef.namespace // "resguardo")=="resguardo")) | {n: .targetRef.name, ip: .addresses[0]} | select(. as $e | any($p[]; . == $e)) | .ip] | sort')
test -n "$LISTOS" && test "$LISTOS" != "[]" || exit 1
$K2 -n resguardo get serviceexport consigna -o json 2>/dev/null | jq -e '[.status.conditions[] | select((.type=="Valid" or .type=="Ready") and .status=="True")] | length == 2' >/dev/null || exit 1
# En uno: no hay ServiceExport ni Service consigna, lo que uno importa viene solo de dos y cada agente de uno
# reparte hacia IP de Pods de dos (10.41.0.0/16), entre ellas un extremo listo de consigna.
$K1 -n resguardo get serviceexport consigna >/dev/null 2>&1 && exit 1
$K1 -n resguardo get service consigna >/dev/null 2>&1 && exit 1
IMP=$($K1 -n resguardo get serviceimport consigna -o json 2>/dev/null)
test -n "$IMP" || exit 1
echo "$IMP" | jq -e '[.status.clusters[].cluster] == ["ckne-lab3-dos"]' >/dev/null || exit 1
IIP=$(echo "$IMP" | jq -r '.spec.ips[0] // empty')
test -n "$IIP" || exit 1
for AG in $($K1 -n kube-system get pods -l k8s-app=cilium -o name); do
  B=$($K1 -n kube-system exec "$AG" -c cilium-agent -- cilium-dbg service list 2>/dev/null | awk -v f="$IIP:80/TCP" '$2 != "=>" {m = ($2 == f)} m && /=>/ {print}' | grep -oE '[0-9.]+:[0-9]+/TCP \(active\)' | cut -d: -f1 | sort | jq -R . | jq -sc .)
  echo "$B" | jq -e --argjson l "$LISTOS" 'length >= 1 and all(.[]; startswith("10.41.")) and any(.[]; . as $x | $l | index($x) != null)' >/dev/null || exit 1
done
# Una sonda nueva en uno (espacio cartas) pide el nombre clusterset.local de consigna.
S="sonda-$RANDOM$RANDOM"
$K1 -n cartas run "$S" --image=$BUSYBOX --restart=Never --command -- sh -c 'nslookup consigna.resguardo.svc.clusterset.local 2>&1 | grep "^Address" | tail -1; for i in 1 2 3 4 5; do echo "R=$(wget -qO- -T3 http://consigna.resguardo.svc.clusterset.local/)"; done' >/dev/null 2>&1 || exit 1
$K1 -n cartas wait --for=jsonpath='{.status.phase}'=Succeeded pod/$S --timeout=120s >/dev/null 2>&1
OUT=$($K1 -n cartas logs "$S" 2>/dev/null)
$K1 -n cartas delete pod "$S" --ignore-not-found >/dev/null 2>&1
echo "$OUT" | grep -qxE "Address:? +$IIP" || exit 1
test "$(echo "$OUT" | grep -cxF "R=$FICHA")" = "5" || exit 1
echo ok
