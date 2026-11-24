#!/usr/bin/env bash
# lab-part-04 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p03"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3"
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c
test -f "$D/03-respuesta.txt" || exit 1
GW=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Gateway}} {{end}}' | tr ' ' '\n' | grep -E '^[0-9.]+$')
IP_FIJA="${GW%.*}.250"
test "$(docker inspect -f '{{.State.Running}}' ckne-lab3-buzon 2>/dev/null)" = "true" || exit 1
BUZON=$(docker inspect -f '{{.NetworkSettings.Networks.kind.IPAddress}}' ckne-lab3-buzon)
test -n "$BUZON" || exit 1
W1=$($K get node ckne-lab3-worker -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
POL=$($K get ciliumegressgatewaypolicy noche-con-ip-fija -o json 2>/dev/null)
test -n "$POL" || exit 1
echo "$POL" | jq -e --arg ip "$IP_FIJA" --arg b "$BUZON/32" '.spec.egressGateway.egressIP==$ip and (.spec.destinationCIDRs | index($b) != null) and (.spec.selectors | length == 1) and .spec.selectors[0].podSelector.matchLabels=={"turno":"noche","io.kubernetes.pod.namespace":"envios"}' >/dev/null || exit 1
NSEL=$(echo "$POL" | jq -r '.spec.egressGateway.nodeSelector.matchLabels | to_entries | map("\(.key)=\(.value)") | join(",")')
test -n "$NSEL" || exit 1
test "$($K get nodes -l "$NSEL" -o jsonpath='{.items[*].metadata.name}')" = "ckne-lab3-worker2" || exit 1
docker exec ckne-lab3-worker2 ip -4 -o addr show eth0 | grep -qF " $IP_FIJA/" || exit 1
for P in remitente testigo; do
  $K -n envios get pod $P -o json 2>/dev/null | jq -e '.status.phase=="Running" and .spec.nodeName=="ckne-lab3-worker" and (.spec.hostNetwork != true)' >/dev/null || exit 1
done
test "$($K -n envios get pod remitente -o jsonpath='{.metadata.labels.turno}')" = "noche" || exit 1
test -z "$($K -n envios get pod testigo -o jsonpath='{.metadata.labels.turno}')" || exit 1
# Se comprueba en el destino: cada pedido lleva una ruta unica y se busca en el registro del buzon.
quien() { # pod ruta -> IP de origen que anoto el buzon
  $K -n envios exec "$1" -- curl -s -m 5 -o /dev/null "http://$BUZON/$2" >/dev/null 2>&1
  sleep 1
  docker logs ckne-lab3-buzon 2>/dev/null | awk -v r="/$2" '$7==r {print $1}' | tail -1
}
R=$RANDOM$RANDOM
test "$(quien remitente r-$R)" = "$IP_FIJA" || exit 1
test "$(quien testigo t-$R)" = "$W1" || exit 1
# Dos sondas nuevas en el mismo trabajador, con y sin la etiqueta: la politica actua por etiqueta.
for E in con sin; do
  L=""; [ "$E" = con ] && L="--labels=turno=noche"
  $K -n envios run sonda-$E-$R --image=$CURL $L --restart=Never --overrides='{"spec":{"nodeName":"ckne-lab3-worker"}}' --command -- sh -c "sleep 4; curl -s -m 5 -o /dev/null http://$BUZON/s-$E-$R" >/dev/null 2>&1 || exit 1
done
for E in con sin; do
  $K -n envios wait --for=jsonpath='{.status.phase}'=Succeeded pod/sonda-$E-$R --timeout=120s >/dev/null 2>&1
  $K -n envios delete pod sonda-$E-$R --ignore-not-found >/dev/null 2>&1
done
test "$(docker logs ckne-lab3-buzon 2>/dev/null | awk -v r="/s-con-$R" '$7==r {print $1}' | tail -1)" = "$IP_FIJA" || exit 1
test "$(docker logs ckne-lab3-buzon 2>/dev/null | awk -v r="/s-sin-$R" '$7==r {print $1}' | tail -1)" = "$W1" || exit 1
AGENTE=$($K -n kube-system get pod -l k8s-app=cilium --field-selector spec.nodeName=ckne-lab3-worker2 -o name)
RIP=$($K -n envios get pod remitente -o jsonpath='{.status.podIP}')
$K -n kube-system exec "$AGENTE" -c cilium-agent -- cilium-dbg bpf egress list 2>/dev/null | grep -qE "^$RIP +$BUZON/32 +$IP_FIJA " || exit 1
grep -qxF "IP_FIJA=$IP_FIJA" "$D/03-respuesta.txt" || exit 1
grep -qxF "ORIGEN_DEL_TESTIGO_EN_EL_DESTINO=$W1" "$D/03-respuesta.txt" || exit 1
grep -qxF "NODO_PUERTA=ckne-lab3-worker2" "$D/03-respuesta.txt" || exit 1
echo ok
