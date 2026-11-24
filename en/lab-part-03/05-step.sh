#!/usr/bin/env bash
# lab-part-03 step 5 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cd ~/ckne-lab/p02
K="kubectl --kubeconfig $HOME/ckne-lab/p02/kubeconfig --context kind-ckne-lab2"

# 1) Los tipos de la Gateway API, canal estandar v1.6.1.
$K apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml >/dev/null
$K get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}'

# 2) istioctl 1.32.0, verificando la huella del archivo, e Istio con el perfil minimal.
case "$(uname -m)" in
  x86_64)        ARQ=amd64; SHA=4771175dec92527cd90ddc7edb3b3abcb32ca2f3bc32b31aa31e0b12ad36f897 ;;
  aarch64|arm64) ARQ=arm64; SHA=6ddfad272f4faa34ef5177e568b7473de2b17ac0464668aea93bf8a450fbbc8a ;;
esac
curl -sSL -o istioctl.tar.gz https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-$ARQ.tar.gz
echo "$SHA  istioctl.tar.gz" | sha256sum -c -
mkdir -p bin && tar -xzf istioctl.tar.gz -C bin
./bin/istioctl version --remote=false
./bin/istioctl install --kubeconfig ~/ckne-lab/p02/kubeconfig --set profile=minimal -y
$K get gatewayclass

# 3) La entrada rampa y la ruta hacia meteo.
cat <<'EOF' | $K apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: rampa
  namespace: cabina
  annotations:
    networking.istio.io/service-type: ClusterIP
spec:
  gatewayClassName: istio
  listeners:
  - name: web
    protocol: HTTP
    port: 80
    hostname: "*.cabina.example"
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: meteo
  namespace: cabina
spec:
  parentRefs:
  - name: rampa
  hostnames:
  - meteo.cabina.example
  rules:
  - backendRefs:
    - name: meteo
      port: 80
EOF
$K -n cabina wait --for=condition=Programmed gateway/rampa --timeout=180s
$K -n cabina rollout status deployment/rampa-istio --timeout=180s
$K -n cabina get service rampa-istio
sleep 5
$K -n cabina get httproute meteo -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'
$K -n cabina exec piloto -- wget -qO- -T5 --header "Host: meteo.cabina.example" http://rampa-istio.cabina/
$K -n cabina exec piloto -- wget -qO- -T5 --header "Host: otro.cabina.example" http://rampa-istio.cabina/ || true

# The answer file the lab asks you to type, written from the live cluster:
D="$HOME/ckne-lab/p02"
cat > "$D/05-respuesta.txt" <<RESP
SERVICIO_DE_LA_ENTRADA=$($K -n cabina get service -l gateway.networking.k8s.io/gateway-name=rampa -o jsonpath='{.items[0].metadata.name}')
CLASE_DE_LA_ENTRADA=$($K -n cabina get gateway rampa -o jsonpath='{.spec.gatewayClassName}')
RUTA_ACEPTADA=$($K -n cabina get httproute meteo -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}')
RESP
cat "$D/05-respuesta.txt"
