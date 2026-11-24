#!/usr/bin/env bash
# lab-part-03 step 3 - grader
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

# The grader reports through its own explicit `exit 1` lines (and prints ok at the end).
set +e
D="$HOME/ckne-lab/p02"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab2"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0
test -f "$D/.falla-aplicada" || exit 1
test -f "$D/03-diagnostico.txt" || exit 1
test -f "$D/03-respuesta.txt" || exit 1
DNS=$($K -n kube-system get service kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
CIP=$($K -n cabina get service meteo -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
test -n "$DNS" && test -n "$CIP" || exit 1
grep -qF "write to '$DNS': Connection refused" "$D/03-diagnostico.txt" || exit 1
grep -qE '^Server:[[:space:]]+192\.168\.[0-9]+\.[0-9]+$' "$D/03-diagnostico.txt" || exit 1
grep -qxF "Address: $CIP" "$D/03-diagnostico.txt" || exit 1
grep -F '"kube-system/kube-dns:dns"' "$D/03-diagnostico.txt" | grep -qE 'DNAT --to-destination 192\.168\.[0-9]+\.[0-9]+:5353$' || exit 1
grep -qxF "dns UDP 53 -> 5353" "$D/03-diagnostico.txt" || exit 1
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
    command: ["sh","-c","nslookup meteo.cabina.svc.cluster.local; true"]
EOF
$K -n cabina wait --for=jsonpath='{.status.phase}'=Succeeded pod/$SONDA --timeout=90s >/dev/null 2>&1
SALIDA=$($K -n cabina logs "$SONDA" 2>/dev/null)
$K -n cabina delete pod "$SONDA" --ignore-not-found >/dev/null 2>&1
DESTINO=$($K -n kube-system get service kube-dns -o jsonpath='{.spec.ports[?(@.name=="dns")].targetPort}')
if [ "$DESTINO" = "5353" ]; then
  echo "$SALIDA" | grep -qxF "Address: $CIP" && exit 1
else
  echo "$SALIDA" | grep -qxF "Address: $CIP" || exit 1
fi
grep -qxF "SERVICIO_CON_FALLA=kube-dns" "$D/03-respuesta.txt" || exit 1
grep -qxF "PROTOCOLO_QUE_FALLA=UDP" "$D/03-respuesta.txt" || exit 1
grep -qxF "PUERTO_EN_LA_LISTA=5353" "$D/03-respuesta.txt" || exit 1
grep -qxF "PUERTO_DE_COREDNS=53" "$D/03-respuesta.txt" || exit 1
grep -qxF "RESPUESTA_DEL_CLIENTE=rechazada" "$D/03-respuesta.txt" || exit 1
echo ok
