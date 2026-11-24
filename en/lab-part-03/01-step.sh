#!/usr/bin/env bash
# lab-part-03 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p02
K="kubectl --kubeconfig $HOME/ckne-lab/p02/kubeconfig --context kind-ckne-lab2"
BUSYBOX=busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0

cat > kind-lab2.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
networking:
  disableDefaultCNI: true
  podSubnet: 192.168.0.0/16
EOF

kind create cluster --name ckne-lab2 \
  --kubeconfig ~/ckne-lab/p02/kubeconfig \
  --image kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5 \
  --config kind-lab2.yaml

$K create -f https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml >/dev/null
$K -n kube-system rollout status daemonset/calico-node --timeout=300s
$K wait --for=condition=Ready node --all --timeout=180s
$K -n kube-system rollout status deployment/coredns --timeout=180s

$K create namespace cabina
cat <<EOF | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: meteo, namespace: cabina}
spec:
  replicas: 3
  selector: {matchLabels: {app: meteo}}
  template:
    metadata: {labels: {app: meteo}}
    spec:
      containers:
      - name: meteo
        image: $BUSYBOX
        command: ["sh","-c","mkdir -p /www && hostname > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports: [{name: web, containerPort: 8080}]
        readinessProbe: {httpGet: {path: /, port: web}, periodSeconds: 3}
---
apiVersion: v1
kind: Service
metadata: {name: meteo, namespace: cabina}
spec:
  selector: {app: meteo}
  ports: [{name: http, port: 80, targetPort: web}]
---
apiVersion: v1
kind: Pod
metadata: {name: piloto, namespace: cabina}
spec:
  containers: [{name: c, image: $BUSYBOX, command: ["sleep","7200"]}]
EOF
$K -n cabina rollout status deployment/meteo --timeout=180s
$K -n cabina wait --for=condition=Ready pod/piloto --timeout=120s

$K -n cabina get svc meteo
$K -n cabina get endpointslice -l kubernetes.io/service-name=meteo \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} {.targetRef.name} ready={.conditions.ready}{"\n"}{end}'
$K -n cabina get endpointslice -l kubernetes.io/service-name=meteo -o jsonpath='{.items[0].ports}{"\n"}'
$K -n cabina exec piloto -- wget -qO- -T5 http://meteo.cabina.svc.cluster.local/

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p02"
cat > "$D/01-respuesta.txt" <<RESP
CLUSTER_IP_DE_METEO=$($K -n cabina get service meteo -o jsonpath='{.spec.clusterIP}')
EXTREMOS_LISTOS=$($K -n cabina get endpointslice -l kubernetes.io/service-name=meteo -o json | jq '[.items[].endpoints[] | select(.conditions.ready==true)] | length')
PUERTO_DE_LOS_EXTREMOS=$($K -n cabina get endpointslice -l kubernetes.io/service-name=meteo -o jsonpath='{.items[0].ports[0].port}')
RESP
cat "$D/01-respuesta.txt"
