#!/usr/bin/env bash
# lab-part-06 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p05
D="$HOME/ckne-lab/p05"
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab6-torre"
. ./pedido.txt

# Una segunda aplicacion detras de la misma entrada: la bascula de pesaje, con su propio nombre.
cat <<YAML | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: pesaje, namespace: faena}
spec:
  replicas: 1
  selector: {matchLabels: {app: pesaje}}
  template:
    metadata: {labels: {app: pesaje}}
    spec:
      containers:
      - name: web
        image: mccutchen/go-httpbin:2.26.0
        ports: [{containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: pesaje, namespace: faena}
spec:
  selector: {app: pesaje}
  ports: [{port: 80, targetPort: 8080}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: ruta-pesaje, namespace: faena}
spec:
  parentRefs: [{name: entrada-torre}]
  hostnames: ["pesaje.torre.test"]
  rules:
  - backendRefs: [{name: pesaje, port: 80}]
YAML
$K -n faena rollout status deployment/pesaje --timeout=180s
sleep 5

# PESAJES_RAPIDOS peticiones a /get y PESAJES_LENTOS a /delay/2, que tarda dos segundos en contestar.
$K -n externo exec sondeo -- sh -c "
  for i in \$(seq $PESAJES_RAPIDOS); do curl -s -o /dev/null -w '%{http_code} %{time_total}\n' -H 'Host: pesaje.torre.test' http://entrada-torre-istio.faena/get; done
  for i in \$(seq $PESAJES_LENTOS); do curl -s -o /dev/null -w '%{http_code} %{time_total}\n' -H 'Host: pesaje.torre.test' http://entrada-torre-istio.faena/delay/2; done"
sleep 30

# Las cubetas del histograma de duracion de la entrada para pesaje, ordenadas por su limite.
bash pregunta.sh 'sum by (le) (istio_request_duration_milliseconds_bucket{reporter="source",destination_service_name="pesaje"})' | sort -g | tee cubetas.txt

# The answer file the lab asks you to type, from the buckets read above:
D="$HOME/ckne-lab/p05"
cat > "$D/04-respuesta.txt" <<RESP
HASTA_1000_MS=$(awk '$1=="1000.0" {print $2}' "$D/cubetas.txt")
HASTA_2500_MS=$(awk '$1=="2500.0" {print $2}' "$D/cubetas.txt")
ENTRE_1000_Y_2500_MS=$(awk '$1=="1000.0" {a=$2} $1=="2500.0" {b=$2} END {print b-a}' "$D/cubetas.txt")
OBSERVACIONES=$(awk '$1=="+Inf" {print $2}' "$D/cubetas.txt")
RESP
cat "$D/04-respuesta.txt"
