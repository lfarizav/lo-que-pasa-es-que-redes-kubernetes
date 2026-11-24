#!/usr/bin/env bash
# lab-part-06 step 5 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p05
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
MARCA=$(cat marca.txt)

# El destino de las trazas: Jaeger 2.23.0 y el Collector 0.165.0, que le reenvia lo que recibe por OTLP.
$K create namespace registro
cat <<YAML | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: jaeger, namespace: registro}
spec:
  selector: {matchLabels: {app: jaeger}}
  template:
    metadata: {labels: {app: jaeger}}
    spec:
      containers:
      - {name: jaeger, image: "jaegertracing/jaeger:2.23.0"}
---
apiVersion: v1
kind: Service
metadata: {name: jaeger, namespace: registro}
spec:
  selector: {app: jaeger}
  ports:
  - {name: grpc-otlp, port: 4317}
  - {name: http-query, port: 16686}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: colector, namespace: registro}
data:
  config.yaml: |
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
    exporters:
      otlp_grpc:
        endpoint: jaeger.registro:4317
        tls:
          insecure: true
    service:
      pipelines:
        traces:
          receivers: [otlp]
          exporters: [otlp_grpc]
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: colector, namespace: registro}
spec:
  selector: {matchLabels: {app: colector}}
  template:
    metadata: {labels: {app: colector}}
    spec:
      containers:
      - name: otelcol
        image: otel/opentelemetry-collector:0.165.0
        args: ["--config=/conf/config.yaml"]
        volumeMounts: [{name: conf, mountPath: /conf}]
      volumes: [{name: conf, configMap: {name: colector}}]
---
apiVersion: v1
kind: Service
metadata: {name: colector, namespace: registro}
spec:
  selector: {app: colector}
  ports: [{name: grpc-otlp, port: 4317}]
YAML
$K -n registro rollout status deployment/jaeger --timeout=180s
$K -n registro rollout status deployment/colector --timeout=180s

# Toda la malla traza al 100 por ciento y escribe el registro de acceso en JSON.
cat <<YAML | $K apply -f -
apiVersion: telemetry.istio.io/v1
kind: Telemetry
metadata: {name: todo-el-trafico, namespace: istio-system}
spec:
  tracing:
  - providers: [{name: trazador}]
    randomSamplingPercentage: 100
  accessLogging:
  - providers: [{name: registro-json}]
YAML

# Una tercera aplicacion, esta vez dentro de la malla (con sidecar), y su entrada.
$K create namespace trazado
$K label namespace trazado istio-injection=enabled
cat <<YAML | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: paquetes, namespace: trazado}
spec:
  replicas: 1
  selector: {matchLabels: {app: paquetes}}
  template:
    metadata: {labels: {app: paquetes}}
    spec:
      containers:
      - name: web
        image: mccutchen/go-httpbin:2.26.0
        ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: paquetes, namespace: trazado}
spec:
  selector: {app: paquetes}
  ports: [{name: http, port: 80, targetPort: 8080}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: entrada-trazas
  namespace: trazado
  annotations: {networking.istio.io/service-type: ClusterIP}
spec:
  gatewayClassName: istio
  listeners:
  - {name: http, port: 80, protocol: HTTP}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: ruta-paquetes, namespace: trazado}
spec:
  parentRefs: [{name: entrada-trazas}]
  hostnames: ["paquetes.torre.test"]
  rules:
  - backendRefs: [{name: paquetes, port: 80}]
YAML
$K -n trazado rollout status deployment/paquetes --timeout=240s
$K -n trazado wait --for=condition=Programmed gateway/entrada-trazas --timeout=180s

# tramos.jq: una linea por tramo de una traza (servicio, tipo, microsegundos, nombre, identificador y padre).
cat > tramos.jq <<'JQ'
.result.resourceSpans[]
| (.resource.attributes[] | select(.key == "service.name") | .value.stringValue) as $svc
| .scopeSpans[].spans[]
| "\($svc) \({"2": "SERVER", "3": "CLIENT"}[.kind | tostring]) \((.endTimeUnixNano[:-3] | tonumber) - (.startTimeUnixNano[:-3] | tonumber)) us",
  "  \(.name | sub(".svc.cluster.local"; ""))",
  "  id \(.spanId) padre \(.parentSpanId // "-")"
JQ

# Una peticion con la marca de esta corrida en la ruta, por la entrada de la malla.
$K -n externo exec sondeo -- curl -s -o /dev/null -w "%{http_code}\n" -H "Host: paquetes.torre.test" http://entrada-trazas-istio.trazado/anything/$MARCA
sleep 8
echo "LA LINEA DEL REGISTRO DE ACCESO de la entrada:"
$K -n trazado logs deploy/entrada-trazas-istio | grep '^{' | jq -c "select(.ruta | endswith(\"$MARCA\"))"
T=$($K -n trazado logs deploy/entrada-trazas-istio | grep '^{' | jq -r "select(.ruta | endswith(\"$MARCA\")) | .traza" | tail -1)
echo "traza: $T"
echo "LA LINEA DEL SIDECAR de paquetes, con el mismo numero:"
$K -n trazado logs deploy/paquetes -c istio-proxy | grep '^{' | jq -c "select(.traza == \"$T\")"
sleep 8
echo "LA TRAZA en Jaeger:"
$K -n externo exec sondeo -- curl -s http://jaeger.registro:16686/api/v3/traces/$T | jq -r -f tramos.jq

# The answer file the lab asks you to type, from the access log line and Jaeger's trace:
D="$HOME/ckne-lab/p05"
cat > "$D/05-respuesta.txt" <<RESP
TRAZA=$T
TRAMOS=$($K -n externo exec sondeo -- curl -s http://jaeger.registro:16686/api/v3/traces/$T | jq '[.result.resourceSpans[].scopeSpans[].spans[]] | length')
TRAMO_RAIZ=$($K -n externo exec sondeo -- curl -s http://jaeger.registro:16686/api/v3/traces/$T | jq -r '.result.resourceSpans[].scopeSpans[].spans[] | select((.parentSpanId // "") == "") | .spanId')
RESP
cat "$D/05-respuesta.txt"
