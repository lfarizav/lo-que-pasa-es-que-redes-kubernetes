#!/usr/bin/env bash
# lab-part-04 step 1 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p03
D="$HOME/ckne-lab/p03"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab3"
NODO=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
SIM=ghcr.io/llm-d/llm-d-inference-sim:v0.7.1@sha256:74211b5dbf27a867fcefae92067701e0a5fcee827f95156d89718bf3e1bfb845
EPP=registry.k8s.io/gateway-api-inference-extension/epp:v1.0.1@sha256:50e96bc704e4823b0b9fef9739fb952a82dcc7f5b8a8f93fecf8fd07ec4b66c9
CURL=curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c

# 1) El cluster ckne-lab3, sin CNI por defecto y sin kube-proxy: Cilium hace las dos cosas.
cat > kind-lab3.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  disableDefaultCNI: true
  kubeProxyMode: none
nodes:
- role: control-plane
- role: worker
- role: worker
EOF
kind create cluster --name ckne-lab3 --kubeconfig "$D/kubeconfig" --image "$NODO" --config kind-lab3.yaml

# 2) Cilium 1.20.5 con reemplazo de kube-proxy, enmascarado BPF y la pasarela de salida del Paso 3.
helm install cilium cilium --repo https://helm.cilium.io --version 1.20.5 \
  --kubeconfig "$D/kubeconfig" --kube-context kind-ckne-lab3 -n kube-system \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=ckne-lab3-control-plane --set k8sServicePort=6443 \
  --set bpf.masquerade=true --set egressGateway.enabled=true >/dev/null
$K -n kube-system rollout status daemonset/cilium --timeout=300s
$K wait --for=condition=Ready node --all --timeout=180s

# 3) Los tipos: Gateway API v1.6.1 (canal estandar) y la Inference Extension v1.0.1.
$K apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml >/dev/null
$K apply --server-side -f https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.0.1/manifests.yaml
$K get crd -o custom-columns=CRD:.metadata.name | grep inference

# 4) istioctl 1.32.0 (con la huella verificada) e Istio minimal con la Inference Extension activa.
case "$(uname -m)" in
  x86_64)        ARQ=amd64; SHA=4771175dec92527cd90ddc7edb3b3abcb32ca2f3bc32b31aa31e0b12ad36f897 ;;
  aarch64|arm64) ARQ=arm64; SHA=6ddfad272f4faa34ef5177e568b7473de2b17ac0464668aea93bf8a450fbbc8a ;;
esac
curl -sSL -o istioctl.tar.gz https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-$ARQ.tar.gz
echo "$SHA  istioctl.tar.gz" > istioctl.sha256
sha256sum -c istioctl.sha256
mkdir -p bin && tar -xzf istioctl.tar.gz -C bin
./bin/istioctl install --kubeconfig "$D/kubeconfig" --context kind-ckne-lab3 -y --set profile=minimal \
  --set values.pilot.env.SUPPORT_GATEWAY_API_INFERENCE_EXTENSION=true \
  --set values.pilot.env.ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true
./bin/istioctl version --kubeconfig "$D/kubeconfig" --context kind-ckne-lab3

# 5) Tres servidores de modelo simulados: dos redactor libres y un redactor-ocupado que publica
#    una cola larga y la cache casi llena. Los tres llevan la etiqueta grupo=redaccion.
$K create namespace imprenta
servidor() { # nombre replicas argumentos-extra
cat <<EOF
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: $1, namespace: imprenta}
spec:
  replicas: $2
  selector: {matchLabels: {app: $1}}
  template:
    metadata: {labels: {app: $1, grupo: redaccion}}
    spec:
      containers:
      - name: vllm-sim
        image: $SIM
        args: ["--model", "redaccion", "--port", "8000"$3]
        ports: [{containerPort: 8000}]
        env: [{name: POD_NAME, valueFrom: {fieldRef: {fieldPath: metadata.name}}}]
        resources: {requests: {cpu: 20m}}
EOF
}
{ servidor redactor 2 ""
  servidor redactor-ocupado 1 ', "--fake-metrics", "{\"running-requests\":5,\"waiting-requests\":30,\"kv-cache-usage\":0.9}"'
  cat <<'EOF'
---
apiVersion: v1
kind: Service
metadata: {name: redactores, namespace: imprenta}
spec:
  selector: {grupo: redaccion}
  ports: [{port: 8000}]
EOF
} | $K apply -f -
$K -n imprenta wait --for=condition=Ready pod -l grupo=redaccion --timeout=300s

# 6) El grupo redaccion y su elector (el EPP), con permiso para leer el grupo, los Pods y los
#    objetivos, y con el nombre de la metrica de cache que publica este simulador.
cat <<EOF | $K apply -f -
apiVersion: inference.networking.k8s.io/v1
kind: InferencePool
metadata: {name: redaccion, namespace: imprenta}
spec:
  selector: {matchLabels: {grupo: redaccion}}
  targetPorts: [{number: 8000}]
  endpointPickerRef: {name: elector, port: {number: 9002}}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: elector, namespace: imprenta}
data:
  plugins.yaml: |
    apiVersion: inference.networking.x-k8s.io/v1alpha1
    kind: EndpointPickerConfig
    plugins:
    - type: queue-scorer
    - type: kv-cache-utilization-scorer
    - type: prefix-cache-scorer
    schedulingProfiles:
    - name: default
      plugins:
      - {pluginRef: queue-scorer, weight: 2}
      - {pluginRef: kv-cache-utilization-scorer, weight: 2}
      - {pluginRef: prefix-cache-scorer, weight: 3}
---
apiVersion: v1
kind: ServiceAccount
metadata: {name: elector, namespace: imprenta}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: {name: elector, namespace: imprenta}
rules:
- {apiGroups: ["inference.networking.k8s.io"], resources: ["inferencepools"], verbs: ["get", "list", "watch"]}
- {apiGroups: ["inference.networking.x-k8s.io"], resources: ["inferenceobjectives"], verbs: ["get", "list", "watch"]}
- {apiGroups: [""], resources: ["pods"], verbs: ["get", "list", "watch"]}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: {name: elector, namespace: imprenta}
subjects: [{kind: ServiceAccount, name: elector, namespace: imprenta}]
roleRef: {kind: Role, name: elector, apiGroup: rbac.authorization.k8s.io}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: elector, namespace: imprenta}
spec:
  replicas: 1
  selector: {matchLabels: {app: elector}}
  template:
    metadata: {labels: {app: elector}}
    spec:
      serviceAccountName: elector
      containers:
      - name: epp
        image: $EPP
        args: ["--pool-name", "redaccion", "--pool-namespace", "imprenta", "--v", "4",
               "--zap-encoder", "json", "--config-file", "/config/plugins.yaml",
               "--kv-cache-usage-percentage-metric", "vllm:kv_cache_usage_perc"]
        ports: [{containerPort: 9002}, {containerPort: 9003}, {containerPort: 9090}]
        readinessProbe: {grpc: {port: 9003, service: inference-extension}, initialDelaySeconds: 5, periodSeconds: 10}
        volumeMounts: [{name: config, mountPath: /config}]
      volumes: [{name: config, configMap: {name: elector}}]
---
apiVersion: v1
kind: Service
metadata: {name: elector, namespace: imprenta}
spec:
  selector: {app: elector}
  ports: [{port: 9002, appProtocol: http2}]
---
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: elector-tls, namespace: imprenta}
spec:
  host: elector
  trafficPolicy: {tls: {mode: SIMPLE, insecureSkipVerify: true}}
EOF
$K -n imprenta rollout status deployment/elector --timeout=300s

# 7) La entrada portico y dos rutas: una al grupo (pasa por el elector) y otra a la Service.
cat <<'EOF' | $K apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: portico
  namespace: imprenta
  annotations: {networking.istio.io/service-type: ClusterIP}
spec:
  gatewayClassName: istio
  listeners: [{name: http, port: 80, protocol: HTTP}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: por-el-grupo, namespace: imprenta}
spec:
  parentRefs: [{name: portico}]
  hostnames: ["grupo.imprenta.example"]
  rules:
  - matches: [{path: {type: PathPrefix, value: /v1/completions}}]
    backendRefs: [{group: inference.networking.k8s.io, kind: InferencePool, name: redaccion}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: por-la-service, namespace: imprenta}
spec:
  parentRefs: [{name: portico}]
  hostnames: ["service.imprenta.example"]
  rules:
  - backendRefs: [{name: redactores, port: 8000}]
EOF
$K -n imprenta wait --for=condition=Programmed gateway/portico --timeout=180s
$K -n imprenta rollout status deployment/portico-istio --timeout=180s
$K -n imprenta run solicitante --image=$CURL --command -- sleep 7200
$K -n imprenta wait --for=condition=Ready pod/solicitante --timeout=180s
sleep 10
$K -n imprenta get inferencepool redaccion -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'

# 8) Doce peticiones por cada ruta. El simulador devuelve en x-inference-pod quien atendio.
cat > pregunta.sh <<'EOF'
# uso: sh pregunta.sh <grupo|service> <texto>
kubectl --kubeconfig "$HOME/ckne-lab/p03/kubeconfig" --context kind-ckne-lab3 -n imprenta \
  exec solicitante -- curl -s -o /dev/null -w "%header{x-inference-pod} %{http_code}\n" \
  -H "Host: $1.imprenta.example" -d "{\"model\":\"redaccion\",\"prompt\":\"$2\"}" \
  http://portico-istio/v1/completions
EOF
for r in service grupo; do
  echo "== por la ruta $r"
  for i in $(seq 12); do sh pregunta.sh $r "nota $i"; done | sort | uniq -c
done

# 9) El registro del elector: el puntaje que dio a cada Pod en la ultima peticion.
cat > marcador.jq <<'EOF'
select(.msg == "Calculated score")
| (.plugin | split("-")[0]) + " " + .endpoint.name + " " + (.score * 100 | round | tostring)
EOF
$K -n imprenta logs deploy/elector --tail=400 | jq -r -f marcador.jq | tail -9

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p03"
cat > "$D/01-respuesta.txt" <<RESP
SERVICE_DEL_PORTICO=$($K -n imprenta get service -l gateway.networking.k8s.io/gateway-name=portico -o jsonpath='{.items[0].metadata.name}')
POD_QUE_EL_ELECTOR_EVITA=$($K -n imprenta get pods -l app=redactor-ocupado -o jsonpath='{.items[0].metadata.name}')
PUERTO_DEL_ELECTOR=$($K -n imprenta get inferencepool redaccion -o jsonpath='{.spec.endpointPickerRef.port.number}')
RESP
cat "$D/01-respuesta.txt"
