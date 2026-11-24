#!/usr/bin/env bash
# lab-part-03 step 4 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p02"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab2"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/04-respuesta.txt" || exit 1
test -f "$D/.corefile.sha256" || exit 1
SVC=$($K -n kube-system get service kube-dns -o json 2>/dev/null)
test -n "$SVC" || exit 1
DNS=$(echo "$SVC" | jq -r '.spec.clusterIP')
test "$DNS" = "10.96.0.10" || exit 1
test "$(echo "$SVC" | jq -c '.spec.selector')" = '{"k8s-app":"kube-dns"}' || exit 1
test "$(echo "$SVC" | jq -r '[.spec.ports[] | "\(.name)/\(.protocol)/\(.port)/\(.targetPort)"] | sort | join(",")')" = "dns-tcp/TCP/53/53,dns/UDP/53/53,metrics/TCP/9153/9153" || exit 1
$K -n kube-system get endpointslice -l kubernetes.io/service-name=kube-dns -o json | jq -e '[.items[].ports[] | select(.name=="dns" and .protocol=="UDP" and .port==53)] | length >= 1' >/dev/null || exit 1
test "$($K -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | sha256sum | cut -d' ' -f1)" = "$(cat "$D/.corefile.sha256")" || exit 1
test "$($K -n kube-system get deployment coredns -o jsonpath='{.status.readyReplicas}')" = "2" || exit 1
for N in ckne-lab2-control-plane ckne-lab2-worker ckne-lab2-worker2; do
  docker exec "$N" grep -A1 '^clusterDNS:' /var/lib/kubelet/config.yaml | grep -qxF -- "- 10.96.0.10" || exit 1
  docker exec "$N" iptables-save -t nat 2>/dev/null | grep -F '"kube-system/kube-dns:dns"' | grep -qE ':5353$' && exit 1
done
PIL=$($K -n cabina get pod piloto -o json 2>/dev/null)
test -n "$PIL" || exit 1
echo "$PIL" | jq -e '(.spec.dnsPolicy == "ClusterFirst") and (.spec.dnsConfig == null)' >/dev/null || exit 1
CIP=$($K -n cabina get service meteo -o jsonpath='{.spec.clusterIP}')
VIVOS=$($K -n cabina get pods -l app=meteo -o jsonpath='{.items[*].metadata.name}')
SONDA="sonda-$RANDOM$RANDOM"
cat <<EOF | $K apply -f - >/dev/null || exit 1
apiVersion: v1
kind: Pod
metadata: {name: $SONDA, namespace: cabina}
spec:
  restartPolicy: Never
  containers:
  - name: c
    image: $BUSYBOX
    command: ["sh","-c","nslookup meteo.cabina.svc.cluster.local; echo CUERPO=\$(wget -qO- -T5 http://meteo.cabina.svc.cluster.local/)"]
EOF
$K -n cabina wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
SALIDA=$($K -n cabina logs "$SONDA" 2>/dev/null)
$K -n cabina delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
echo "$SALIDA" | grep -qE "^Server:[[:space:]]+$DNS$" || exit 1
echo "$SALIDA" | grep -qxF "Address: $CIP" || exit 1
CUERPO=$(echo "$SALIDA" | sed -n 's/^CUERPO=//p' | tr -d '\r')
test -n "$CUERPO" || exit 1
echo " $VIVOS " | grep -qF " $CUERPO " || exit 1
grep -qxF "PUERTO_DESTINO_RESTAURADO=53" "$D/04-respuesta.txt" || exit 1
grep -qxF "IP_DEL_DIRECTORIO=$DNS" "$D/04-respuesta.txt" || exit 1
grep -qxF "COREFILE_INTACTO=si" "$D/04-respuesta.txt" || exit 1
echo ok
