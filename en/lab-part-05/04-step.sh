#!/usr/bin/env bash
# lab-part-05 step 4 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p04
D="$HOME/ckne-lab/p04"
NODO=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
NETSHOOT=nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70
K="kubectl --kubeconfig $D/kubeconfig --context kind-ckne-lab5-sello"
H="--kubeconfig $D/kubeconfig --kube-context kind-ckne-lab5-sello"

cat > sello-kind.yaml <<'YAML'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
YAML
kind create cluster --name ckne-lab5-sello --config sello-kind.yaml --image "$NODO" --kubeconfig "$D/kubeconfig"
$K wait --for=condition=Ready node --all --timeout=180s

# Gateway API v1.6.1, istioctl 1.32.0 (con la huella verificada) e Istio minimal, y cert-manager v1.21.3 con la Gateway API activa.
$K apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml >/dev/null
case "$(uname -m)" in
  x86_64)        ARQ=amd64; SHA=4771175dec92527cd90ddc7edb3b3abcb32ca2f3bc32b31aa31e0b12ad36f897 ;;
  aarch64|arm64) ARQ=arm64; SHA=6ddfad272f4faa34ef5177e568b7473de2b17ac0464668aea93bf8a450fbbc8a ;;
esac
curl -sSL -o istioctl.tar.gz https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-$ARQ.tar.gz
echo "$SHA  istioctl.tar.gz" > istioctl.sha256
sha256sum -c istioctl.sha256
mkdir -p bin && tar -xzf istioctl.tar.gz -C bin
./bin/istioctl install --kubeconfig "$D/kubeconfig" --context kind-ckne-lab5-sello -y --set profile=minimal
cat > valores-cert-manager.yaml <<'YAML'
crds:
  enabled: true
config:
  apiVersion: controller.config.cert-manager.io/v1alpha1
  kind: ControllerConfiguration
  gatewayAPI:
    enabled: true
    enableListenerSet: true
  featureGates:
    ListenerSets: true
YAML
helm install cert-manager oci://quay.io/jetstack/charts/cert-manager --version v1.21.3 --namespace cert-manager --create-namespace -f valores-cert-manager.yaml --wait $H >/dev/null

# La autoridad del laboratorio: una raiz propia y un emisor que firma con ella.
cat <<YAML | $K apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: {name: semilla-lab}
spec: {selfSigned: {}}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: {name: raiz-lab, namespace: cert-manager}
spec:
  isCA: true
  commonName: Autoridad del puerto
  secretName: raiz-lab
  duration: 87600h
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {kind: ClusterIssuer, name: semilla-lab}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata: {name: casa-emisora}
spec:
  ca: {secretName: raiz-lab}
YAML
$K -n cert-manager wait certificate/raiz-lab --for=condition=Ready --timeout=60s
$K wait clusterissuer/casa-emisora --for=condition=Ready --timeout=60s

# La aplicacion, la entrada que hoy solo habla en claro y un cliente que lleva la raiz.
$K create namespace dique
$K create namespace ribera
cat <<YAML | $K apply -f -
apiVersion: v1
kind: ConfigMap
metadata: {name: letrero, namespace: ribera}
data:
  default.conf: |
    server {
      listen 8080;
      location / {
        default_type text/plain;
        return 200 "letrero: salida 7 puntual\n";
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: letrero, namespace: ribera}
spec:
  selector: {matchLabels: {app: letrero}}
  template:
    metadata: {labels: {app: letrero}}
    spec:
      containers:
      - name: nginx
        image: nginx:1.29.5-alpine
        volumeMounts: [{name: conf, mountPath: /etc/nginx/conf.d}]
      volumes: [{name: conf, configMap: {name: letrero}}]
---
apiVersion: v1
kind: Service
metadata: {name: letrero, namespace: ribera}
spec:
  selector: {app: letrero}
  ports: [{port: 80, targetPort: 8080}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: entrada-lab
  namespace: dique
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: sin-candado
    protocol: HTTP
    port: 80
    hostname: letrero.lab.example
    allowedRoutes: {namespaces: {from: All}}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: letrero, namespace: ribera}
spec:
  parentRefs: [{name: entrada-lab, namespace: dique}]
  hostnames: [letrero.lab.example]
  rules:
  - backendRefs: [{name: letrero, port: 80}]
---
apiVersion: v1
kind: Pod
metadata: {name: cliente-tls, namespace: ribera}
spec:
  containers: [{name: sh, image: $NETSHOOT, command: ["sleep", "7200"]}]
YAML
$K -n ribera rollout status deployment/letrero --timeout=180s
$K -n ribera wait --for=condition=Ready pod/cliente-tls --timeout=180s
$K -n dique wait gateway/entrada-lab --for=condition=Programmed --timeout=180s
$K -n cert-manager get secret raiz-lab -o jsonpath='{.data.ca\.crt}' | base64 -d > raiz.crt
$K -n ribera cp raiz.crt cliente-tls:/raiz.crt

# Certificado del servidor que presenta el puerto 443 para el nombre $1, visto desde el cliente.
cat > sello.sh <<'SELLO'
K="kubectl --kubeconfig $HOME/ckne-lab/p04/kubeconfig --context kind-ckne-lab5-sello"
$K -n ribera exec cliente-tls -- sh -c "openssl s_client -connect entrada-lab-istio.dique:443 -servername $1 -CAfile /raiz.crt </dev/null 2>/dev/null | openssl x509 -noout -serial -issuer -enddate -ext subjectAltName"
SELLO
cat > conds.jq <<'JQ'
.status.listeners[] | .name as $n | .conditions[]
| select(.type != "Conflicted")
| "\($n) \(.type)=\(.status) \(.reason)"
JQ

$K -n dique rollout status deployment/entrada-lab-istio --timeout=180s
echo "ANTES: un solo listener, sin cifrar"
for i in 1 2 3 4 5 6; do
  $K -n ribera exec cliente-tls -- curl -s -m 3 -H "Host: letrero.lab.example" http://entrada-lab-istio.dique/ && break
  sleep 5
done

# El listener HTTPS lleva la anotacion que le pide el certificado a cert-manager, con su vigencia.
cat <<YAML | $K apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: entrada-lab
  namespace: dique
  annotations:
    networking.istio.io/service-type: ClusterIP
    cert-manager.io/cluster-issuer: casa-emisora
    cert-manager.io/duration: 2h
    cert-manager.io/renew-before: 1h
spec:
  gatewayClassName: istio
  listeners:
  - name: sin-candado
    protocol: HTTP
    port: 80
    hostname: letrero.lab.example
    allowedRoutes: {namespaces: {from: All}}
  - name: con-candado
    protocol: HTTPS
    port: 443
    hostname: letrero.lab.example
    tls:
      mode: Terminate
      certificateRefs:
      - name: letrero-tls
    allowedRoutes: {namespaces: {from: All}}
YAML
$K -n dique wait certificate/letrero-tls --for=condition=Ready --timeout=120s
sleep 10
echo "LAS CONDICIONES de los listeners:"
$K -n dique get gateway entrada-lab -o json | jq -r -f conds.jq
echo "EL CERTIFICADO que sirve el puerto 443:"
bash sello.sh letrero.lab.example
$K -n ribera exec cliente-tls -- curl -s -m 5 --cacert /raiz.crt --connect-to letrero.lab.example:443:entrada-lab-istio.dique:443 https://letrero.lab.example/

# The answer file the lab asks you to type, from the Certificate and the chain served at 443:
D="$HOME/ckne-lab/p04"
cat > "$D/04-respuesta.txt" <<RESP
CERTIFICADO=$($K -n dique get certificate -o jsonpath='{.items[0].metadata.name}')
EMISOR=$($K -n dique get certificate letrero-tls -o jsonpath='{.spec.issuerRef.name}')
REVISION=$($K -n dique get certificate letrero-tls -o jsonpath='{.status.revision}')
SERIE_SERVIDA=$(bash sello.sh letrero.lab.example | sed -n 's/^serial=//p')
RESP
cat "$D/04-respuesta.txt"
