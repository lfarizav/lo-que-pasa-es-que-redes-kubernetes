#!/usr/bin/env bash
# lab-part-04 step 6 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p03
D="$HOME/ckne-lab/p03"
K1="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-uno"
K2="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-dos"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0

# 1) La misma Service relevo, en el espacio cartas de los dos clusteres. Cada replica contesta
#    el nombre de su cluster.
for N in uno dos; do
  KK="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3-$N"
  cat <<EOF | $KK apply -f -
apiVersion: v1
kind: Namespace
metadata: {name: cartas}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: relevo, namespace: cartas}
spec:
  replicas: 2
  selector: {matchLabels: {app: relevo}}
  template:
    metadata: {labels: {app: relevo}}
    spec:
      containers:
      - name: web
        image: $BUSYBOX
        command: ["sh", "-c", "mkdir -p /www && echo ckne-lab3-$N > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: relevo, namespace: cartas}
spec:
  selector: {app: relevo}
  ports: [{port: 80, targetPort: 8080}]
EOF
  $KK -n cartas rollout status deployment/relevo --timeout=180s
done
$K1 -n cartas run explorador --image=$BUSYBOX --command -- sleep 7200
$K1 -n cartas wait --for=condition=Ready pod/explorador --timeout=180s

# 2) Exportar relevo en los dos clusteres. Sin su ServiceExport, un cluster no aporta Pods.
for KK in "$K1" "$K2"; do
  cat <<'EOF' | $KK apply -f -
apiVersion: multicluster.x-k8s.io/v1beta1
kind: ServiceExport
metadata: {name: relevo, namespace: cartas}
EOF
done
until [ "$($K1 -n cartas get serviceimport relevo -o jsonpath='{.status.clusters[*].cluster}' 2>/dev/null | wc -w)" = 2 ]; do sleep 3; done
$K1 -n cartas get serviceimport relevo -o jsonpath='{.spec.type} {.spec.ips[0]} {.status.clusters[*].cluster}{"\n"}'
sleep 10
reparto() {
  $K1 -n cartas exec explorador -- sh -c 'for i in $(seq 20); do wget -qO- -T2 http://relevo.cartas.svc.clusterset.local/ || echo sin-respuesta; done' | sort | uniq -c
}
reparto

# 3) La caida: el clustermesh-apiserver de dos se apaga. Se lee lo que dicen a la vez el agente
#    de uno y KVStoreMesh de uno, y se vuelve a medir el reparto.
$K2 -n kube-system scale deployment clustermesh-apiserver --replicas=0
$K2 -n kube-system wait --for=delete pod -l k8s-app=clustermesh-apiserver --timeout=120s
until ! $K1 -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh -- clustermesh-apiserver kvstoremesh-dbg status 2>/dev/null | grep -q "1/1"; do sleep 5; done
{
  echo "== $(date -u +%FT%TZ) clustermesh-apiserver de ckne-lab3-dos en 0 replicas"
  echo "== agente de Cilium en ckne-lab3-uno"
  $K1 -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status | grep "^ClusterMesh" | tr -s " "
  echo "== KVStoreMesh en ckne-lab3-uno"
  $K1 -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh -- clustermesh-apiserver kvstoremesh-dbg status | head -2
  echo "== reparto durante la caida"
  reparto
} | tee 06-caida.txt

# 4) De vuelta: una replica, y esperar a que KVStoreMesh de uno vuelva a 1/1.
$K2 -n kube-system scale deployment clustermesh-apiserver --replicas=1
$K2 -n kube-system rollout status deployment/clustermesh-apiserver --timeout=300s
until $K1 -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh -- clustermesh-apiserver kvstoremesh-dbg status 2>/dev/null | grep -q "1/1"; do sleep 5; done
$K1 -n kube-system exec deploy/clustermesh-apiserver -c kvstoremesh -- clustermesh-apiserver kvstoremesh-dbg status | head -2
reparto

# The answer file the lab asks you to type, from what 06-caida.txt recorded:
D="$HOME/ckne-lab/p03"
cat > "$D/06-respuesta.txt" <<RESP
AGENTE_DE_UNO_EN_LA_CAIDA=$(grep '^ClusterMesh:' "$D/06-caida.txt" | grep -oE '[0-9]+/[0-9]+')
KVSTOREMESH_DE_UNO_EN_LA_CAIDA=$(grep '^KVStoreMesh:' "$D/06-caida.txt" | grep -oE '[0-9]+/[0-9]+')
DOS_SIGUIO_ATENDIENDO=$(grep -qE '^ +[0-9]+ ckne-lab3-dos$' "$D/06-caida.txt" && echo si || echo no)
RESP
cat "$D/06-respuesta.txt"
