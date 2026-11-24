#!/usr/bin/env bash
# lab-part-05 step 6 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p04
D="$HOME/ckne-lab/p04"
NODO=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-id"
H="--kubeconfig $D/kubeconfig --kube-context kind-ckne-lab5-id"

cat > id-kind.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
YAML
kind create cluster --name ckne-lab5-id --config id-kind.yaml --image "$NODO" --kubeconfig "$D/kubeconfig"
$K wait --for=condition=Ready node --all --timeout=180s

# SPIRE (chart hardened 0.31.0, CRDs 0.6.1) con el dominio de confianza del laboratorio.
R=https://spiffe.github.io/helm-charts-hardened/
helm upgrade --install -n spire-server spire-crds spire-crds --repo $R --version 0.6.1 --create-namespace $H >/dev/null
helm upgrade --install -n spire-server spire spire --repo $R --version 0.31.0 --wait \
  --set global.spire.trustDomain=lab.test --set global.spire.clusterName=ckne-lab5-id $H >/dev/null
$K -n spire-server get pods

# Istio 1.32.0 (el istioctl que bajo el Paso 4) con ese dominio y la plantilla spire, que monta el socket de SPIRE en el sidecar.
cat > malla.yaml <<'YAML'
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  profile: minimal
  meshConfig:
    trustDomain: lab.test
  values:
    sidecarInjectorWebhook:
      templates:
        spire: |
          labels:
            spiffe.io/spire-managed-identity: "true"
          spec:
            initContainers:
            - name: istio-proxy
              volumeMounts:
              - name: workload-socket
                mountPath: /run/secrets/workload-spiffe-uds
                readOnly: true
            volumes:
            - name: workload-socket
              csi:
                driver: "csi.spiffe.io"
                readOnly: true
YAML
./bin/istioctl install --kubeconfig "$D/kubeconfig" --context kind-ckne-lab5-id -y -f malla.yaml
$K -n istio-system get deployment istiod

# Un servidor y un portador con su pase, en un espacio con inyeccion.
$K create namespace cubierta
$K label namespace cubierta istio-injection=enabled
for sa in capitan invitado bascula; do $K -n cubierta create serviceaccount $sa; done
cat <<YAML | $K apply -f -
apiVersion: apps/v1
kind: Deployment
metadata: {name: bascula, namespace: cubierta}
spec:
  selector: {matchLabels: {app: bascula}}
  template:
    metadata:
      labels: {app: bascula}
      annotations:
        inject.istio.io/templates: "sidecar,spire"
    spec:
      serviceAccountName: bascula
      containers:
      - name: nginx
        image: nginx:1.29.5-alpine
        ports: [{containerPort: 80}]
---
apiVersion: v1
kind: Service
metadata: {name: bascula, namespace: cubierta}
spec:
  selector: {app: bascula}
  ports: [{name: http, port: 80}]
---
apiVersion: v1
kind: Pod
metadata:
  name: portador
  namespace: cubierta
  annotations:
    inject.istio.io/templates: "sidecar,spire"
spec:
  serviceAccountName: capitan
  containers:
  - name: sh
    image: nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70
    command: ["sleep", "7200"]
    volumeMounts: [{name: pase, mountPath: /var/run/pase}]
  volumes:
  - name: pase
    projected:
      sources:
      - serviceAccountToken: {audience: bascula, expirationSeconds: 900, path: token}
YAML
$K -n cubierta rollout status deployment/bascula --timeout=240s
$K -n cubierta wait --for=condition=Ready pod/portador --timeout=240s
$K -n cubierta get pods

# 1) El documento de identidad que tiene el sidecar de la bascula.
BP=$($K -n cubierta get pod -l app=bascula -o jsonpath='{.items[0].metadata.name}')
./bin/istioctl --kubeconfig "$D/kubeconfig" --context kind-ckne-lab5-id proxy-config secret -n cubierta $BP -o json \
  | jq -r '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' | base64 -d \
  | openssl x509 -noout -subject -issuer -ext subjectAltName
# 2) Los campos del pase que lleva el portador.
$K -n cubierta exec portador -c sh -- cat /var/run/pase/token \
  | jq -R 'split(".")[1] | @base64d | fromjson | {iss, sub, aud, vida: (.exp - .iat), pod: .["kubernetes.io"].pod.name}'
# 3) Lo que SPIRE registro para los Pods de cubierta.
$K -n spire-server exec spire-server-0 -c spire-server -- spire-server entry show -output json \
  | jq -r '.entries[] | select(.spiffe_id.path | startswith("/ns/cubierta/")) | .spiffe_id.path, "  " + .selectors[0].type + ":" + .selectors[0].value'

# The answer file the lab asks you to type, read from the live sidecar, token and registry:
D="$HOME/ckne-lab/p04"
CERT=$(./bin/istioctl --kubeconfig "$D/kubeconfig" --context kind-ckne-lab5-id proxy-config secret -n cubierta $BP -o json \
  | jq -r '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' | base64 -d)
TOK=$($K -n cubierta exec portador -c sh -- cat /var/run/pase/token | jq -R 'split(".")[1] | @base64d | fromjson')
cat > "$D/06-respuesta.txt" <<RESP
ID_DE_LA_BASCULA=$(echo "$CERT" | openssl x509 -noout -ext subjectAltName | grep -o 'spiffe://[^ ,]*')
EMISOR_DE_LA_IDENTIDAD=$(echo "$CERT" | openssl x509 -noout -subject | grep -o 'O = [A-Za-z]*' | sed 's/O = //')
AUDIENCIA_DEL_PASE=$(echo "$TOK" | jq -r '.aud[0]')
VIDA_DEL_PASE=$(echo "$TOK" | jq -r '.exp - .iat')
ENTRADAS_DE_CUBIERTA=$($K -n spire-server exec spire-server-0 -c spire-server -- spire-server entry show -output json | jq '[.entries[] | select(.spiffe_id.path | startswith("/ns/cubierta/"))] | length')
RESP
cat "$D/06-respuesta.txt"
