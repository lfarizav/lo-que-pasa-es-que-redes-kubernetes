#!/usr/bin/env bash
# lab-part-06 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p05
D="$HOME/ckne-lab/p05"
NODO=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
H="--kubeconfig $D/kubeconfig --kube-context kind-ckne-lab6-torre"

# El cluster: kube-proxy expone sus metricas en todas las interfaces del nodo para que Prometheus las alcance.
cat > torre-kind.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
kubeadmConfigPatches:
- |
  kind: KubeProxyConfiguration
  metricsBindAddress: "0.0.0.0:10249"
nodes:
- role: control-plane
- role: worker
YAML
kind create cluster --name ckne-lab6-torre --config torre-kind.yaml --image "$NODO" --kubeconfig "$D/kubeconfig"
cat > cilium-valores.yaml <<'YAML'
image:
  pullPolicy: IfNotPresent
ipam:
  mode: kubernetes
operator:
  replicas: 1
prometheus:
  enabled: true
YAML
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.5 -n kube-system -f cilium-valores.yaml $H >/dev/null
$K -n kube-system rollout status daemonset/cilium --timeout=300s
$K wait --for=condition=Ready node --all --timeout=180s

# Gateway API v1.6.1, istioctl 1.32.0 (con la huella verificada) e Istio minimal con los proveedores de trazas y de registro que usara el Paso 5.
$K apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml >/dev/null
case "$(uname -m)" in
  x86_64)        ARQ=amd64; SHA=4771175dec92527cd90ddc7edb3b3abcb32ca2f3bc32b31aa31e0b12ad36f897 ;;
  aarch64|arm64) ARQ=arm64; SHA=6ddfad272f4faa34ef5177e568b7473de2b17ac0464668aea93bf8a450fbbc8a ;;
esac
curl -sSL -o istioctl.tar.gz https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-$ARQ.tar.gz
echo "$SHA  istioctl.tar.gz" > istioctl.sha256
sha256sum -c istioctl.sha256
mkdir -p bin && tar -xzf istioctl.tar.gz -C bin
cat > malla.yaml <<'YAML'
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: minimal
  meshConfig:
    enableTracing: true
    extensionProviders:
    - name: trazador
      opentelemetry:
        service: colector.registro.svc.cluster.local
        port: 4317
    - name: registro-json
      envoyFileAccessLog:
        path: /dev/stdout
        logFormat:
          labels:
            respuesta: "%RESPONSE_CODE%"
            bandera: "%RESPONSE_FLAGS%"
            motivo: "%RESPONSE_CODE_DETAILS%"
            nombre: "%REQ(:AUTHORITY)%"
            ruta: "%REQ(:PATH)%"
            traza: "%TRACE_ID%"
            ms: "%DURATION%"
YAML
./bin/istioctl install --kubeconfig "$D/kubeconfig" --context kind-ckne-lab6-torre -y -f malla.yaml

# Prometheus (chart 29.48.0, imagen v3.16.0), cada 10 segundos y con un trabajo propio para kube-proxy.
cat > vigilancia-valores.yaml <<'YAML'
alertmanager:
  enabled: false
kube-state-metrics:
  enabled: false
prometheus-node-exporter:
  enabled: false
prometheus-pushgateway:
  enabled: false
server:
  persistentVolume:
    enabled: false
  global:
    scrape_interval: 10s
scrapeConfigs:
  kubernetes-api-servers:
    enabled: false
  kubernetes-nodes:
    enabled: false
  kubernetes-nodes-cadvisor:
    enabled: false
  kubernetes-service-endpoints-slow:
    enabled: false
  prometheus-pushgateway:
    enabled: false
  kubernetes-services:
    enabled: false
  kubernetes-pods-slow:
    enabled: false
  kube-proxy:
    kubernetes_sd_configs:
    - role: pod
    relabel_configs:
    - source_labels:
      - __meta_kubernetes_pod_label_k8s_app
      action: keep
      regex: kube-proxy
    - source_labels: [__meta_kubernetes_pod_ip]
      target_label: __address__
      replacement: $1:10249
    - source_labels: [__meta_kubernetes_pod_node_name]
      target_label: node
YAML
helm install prometheus prometheus --repo https://prometheus-community.github.io/helm-charts --version 29.48.0 -n vigilancia --create-namespace -f vigilancia-valores.yaml --wait $H >/dev/null

# La aplicacion, su entrada y un cliente fuera del espacio de la aplicacion.
$K create namespace faena
$K create namespace externo
cat <<YAML | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: bodega, namespace: faena}
spec:
  replicas: 1
  selector: {matchLabels: {app: bodega}}
  template:
    metadata: {labels: {app: bodega}}
    spec:
      containers:
      - name: web
        image: mccutchen/go-httpbin:2.26.0
        ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: bodega, namespace: faena}
spec:
  selector: {app: bodega}
  ports: [{port: 80, targetPort: 8080}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: entrada-torre
  namespace: faena
  annotations: {networking.istio.io/service-type: ClusterIP}
spec:
  gatewayClassName: istio
  listeners:
  - {name: http, port: 80, protocol: HTTP}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: ruta-bodega, namespace: faena}
spec:
  parentRefs: [{name: entrada-torre}]
  hostnames: ["bodega.torre.test"]
  rules:
  - backendRefs: [{name: bodega, port: 80}]
---
apiVersion: v1
kind: Pod
metadata: {name: sondeo, namespace: externo}
spec:
  containers: [{name: sh, image: $CURL, command: ["sleep", "7200"]}]
YAML
$K -n faena rollout status deployment/bodega --timeout=180s
$K -n faena wait --for=condition=Programmed gateway/entrada-torre --timeout=180s
$K -n externo wait --for=condition=Ready pod/sondeo --timeout=180s

# pregunta.sh: una consulta PromQL a Prometheus, una linea por serie (valores de etiqueta y el valor).
cat > pregunta.sh <<'PREGUNTA'
K="kubectl --kubeconfig $HOME/ckne-lab/p05/kubeconfig --context kind-ckne-lab6-torre"
$K -n externo exec sondeo -- curl -s http://prometheus-server.vigilancia/api/v1/query --data-urlencode "query=$1" \
  | jq -r '.data.result[] | [(.metric | .[]), (.value[1] | tonumber * 1000 | round / 1000 | tostring)] | join(" ")'
PREGUNTA
sleep 40
bash pregunta.sh 'count by (job) (up)'
for m in prometheus_build_info coredns_build_info cilium_version; do
  echo "$m $(bash pregunta.sh "count by (version) ($m)")"
done
bash pregunta.sh 'count by (tag) (istio_build)'

# The answer file the lab asks you to type, from what Prometheus reports about itself and the components:
D="$HOME/ckne-lab/p05"
cat > "$D/01-respuesta.txt" <<RESP
PROMETHEUS=$(bash pregunta.sh 'count by (version) (prometheus_build_info)' | awk '{print $1}')
COREDNS=$(bash pregunta.sh 'count by (version) (coredns_build_info)' | awk '{print $1}')
CILIUM=$(bash pregunta.sh 'count by (version) (cilium_version)' | awk '{print $1}')
ISTIO=$(bash pregunta.sh 'count by (tag) (istio_build)' | awk '{print $1}')
OBJETIVOS_KUBE_PROXY=$(bash pregunta.sh 'count(up{job="kube-proxy"} == 1)')
RESP
cat "$D/01-respuesta.txt"
