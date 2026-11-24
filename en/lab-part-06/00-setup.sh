#!/usr/bin/env bash
# lab-part-06 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

mkdir -p ~/ckne-lab/p05
cd ~/ckne-lab/p05

for herramienta in kind kubectl docker helm jq curl tar sha256sum base64 od; do
  command -v "$herramienta" >/dev/null 2>&1 || { echo "FALTA: $herramienta - instalelo antes de continuar."; exit 1; }
done

echo "PRUEBA DE SUSTRATO 1 de 5: kind es v0.33.0 o mas nuevo, y helm responde"
kind version
if ! kind version | grep -Eq 'v0\.(33|[4-9][0-9])\.|v[1-9]'; then
  echo "ERROR DE SUSTRATO: KIND-MUY-VIEJO. Este laboratorio fija kind v0.33.0 como minimo."
  exit 1
fi
helm version --short

echo "PRUEBA DE SUSTRATO 2 de 5: no existe ya el cluster de este laboratorio"
echo "clusteres de kind que ya tiene (este laboratorio no los toca):"
kind get clusters
if kind get clusters 2>/dev/null | grep -qx ckne-lab6-torre; then
  echo "ERROR DE SUSTRATO: YA-EXISTE-ckne-lab6-torre. Corra el teardown del laboratorio y repita."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 3 de 5: Docker puede traer las imagenes fijadas"
for IMG in curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c \
           busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 \
           mccutchen/go-httpbin:2.26.0; do
  if ! docker pull "$IMG" >/dev/null; then
    echo "ERROR DE SUSTRATO: SIN-IMAGEN $IMG. Sin ella los pasos con trafico son decoracion."
    exit 1
  fi
done

echo "PRUEBA DE SUSTRATO 4 de 5: se alcanzan los paquetes de Helm, istioctl y los CRD"
for URL in https://helm.cilium.io/index.yaml \
           https://prometheus-community.github.io/helm-charts/index.yaml \
           https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml \
           https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-amd64.tar.gz.sha256; do
  CODIGO=$(curl -sSL -o /dev/null -w '%{http_code}' "$URL")
  if [ "$CODIGO" != "200" ]; then
    echo "ERROR DE SUSTRATO: SIN-DESCARGA (HTTP $CODIGO) en $URL."
    exit 1
  fi
done

echo "PRUEBA DE SUSTRATO 5 de 5: memoria y limites del anfitrion (dos nodos de kind)"
echo "memoria disponible: $(awk '/MemAvailable/ {printf "%d MB", $2/1024}' /proc/meminfo)"
echo "inotify (kind puede fallar si es muy bajo): $(sysctl -n fs.inotify.max_user_instances) instancias"

# Los numeros de esta corrida: cuantas peticiones buenas y cuantas con error (Paso 2), cuantos intentos bloqueados (Paso 3) y cuantos pesajes rapidos y lentos (Paso 4).
A=$(( 12 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 13 ))
B=$(( 3 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 6 ))
N=$(( 4 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 3 ))
R=$(( 6 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 7 ))
S=$(( 3 + $(od -An -N2 -tu2 /dev/urandom | tr -d ' ') % 4 ))
printf 'PEDIDO_200=%s\nPEDIDO_503=%s\nINTENTOS_BLOQUEADOS=%s\nPESAJES_RAPIDOS=%s\nPESAJES_LENTOS=%s\n' "$A" "$B" "$N" "$R" "$S" > ~/ckne-lab/p05/pedido.txt
echo "marca-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')" > ~/ckne-lab/p05/marca.txt

# Ficha de esta corrida para el Paso 7 (distinta en cada corrida).
FICHA="BITACORA-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "$FICHA" > ~/ckne-lab/p05/ficha-de-la-bitacora.txt
echo -n "$FICHA" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p05/.ficha.sha256
chmod 600 ~/ckne-lab/p05/.ficha.sha256

# La falla del Paso 5 se aplica con un guion cuyo contenido va codificado a proposito.
# Es una venda de cortesia para que no lea la falla de corrido: no es un secreto real.
cat > ~/ckne-lab/p05/inyectar-falla.sh <<'EOF_FALLA'
#!/usr/bin/env bash
# Inyecta la falla de este laboratorio. La parte que rompe va codificada a proposito.
set -e
eval "$(echo 'Sz0ia3ViZWN0bCAtLWt1YmVjb25maWcgJEhPTUUvY2tuZS1sYWIvcDA1L2t1YmVjb25maWcgLS1jb250ZXh0IGtpbmQtY2tuZS1sYWI2LXRvcnJlIgpjYXQgPDxZQU1MIHwgJEsgYXBwbHkgLWYgLSA+L2Rldi9udWxsCmFwaVZlcnNpb246IGFwcHMvdjEKa2luZDogRGVwbG95bWVudAptZXRhZGF0YToge25hbWU6IGNvbnNpZ25hLCBuYW1lc3BhY2U6IHRyYXphZG99CnNwZWM6CiAgcmVwbGljYXM6IDEKICBzZWxlY3Rvcjoge21hdGNoTGFiZWxzOiB7YXBwOiBjb25zaWduYX19CiAgdGVtcGxhdGU6CiAgICBtZXRhZGF0YToge2xhYmVsczoge2FwcDogY29uc2lnbmF9fQogICAgc3BlYzoKICAgICAgY29udGFpbmVyczoKICAgICAgLSBuYW1lOiB3ZWIKICAgICAgICBpbWFnZTogbWNjdXRjaGVuL2dvLWh0dHBiaW46Mi4yNi4wCiAgICAgICAgcG9ydHM6IFt7Y29udGFpbmVyUG9ydDogODA4MH1dCi0tLQphcGlWZXJzaW9uOiB2MQpraW5kOiBTZXJ2aWNlCm1ldGFkYXRhOiB7bmFtZTogY29uc2lnbmEsIG5hbWVzcGFjZTogdHJhemFkb30Kc3BlYzoKICBzZWxlY3Rvcjoge2FwcDogY29uc2lnbmEtdjJ9CiAgcG9ydHM6IFt7bmFtZTogaHR0cCwgcG9ydDogODAsIHRhcmdldFBvcnQ6IDgwODB9XQotLS0KYXBpVmVyc2lvbjogZ2F0ZXdheS5uZXR3b3JraW5nLms4cy5pby92MQpraW5kOiBIVFRQUm91dGUKbWV0YWRhdGE6IHtuYW1lOiBydXRhLWNvbnNpZ25hLCBuYW1lc3BhY2U6IHRyYXphZG99CnNwZWM6CiAgcGFyZW50UmVmczogW3tuYW1lOiBlbnRyYWRhLXRyYXphc31dCiAgaG9zdG5hbWVzOiBbImNvbnNpZ25hLnRvcnJlLnRlc3QiXQogIHJ1bGVzOgogIC0gYmFja2VuZFJlZnM6IFt7bmFtZTogY29uc2lnbmEsIHBvcnQ6IDgwfV0KWUFNTAokSyAtbiB0cmF6YWRvIHJvbGxvdXQgc3RhdHVzIGRlcGxveW1lbnQvY29uc2lnbmEgLS10aW1lb3V0PTI0MHMgPi9kZXYvbnVsbApmb3IgaSBpbiAkKHNlcSAyMCk7IGRvCiAgVUlEX1M9JCgkSyAtbiB0cmF6YWRvIGdldCBzZXJ2aWNlIGNvbnNpZ25hIC1vIGpzb25wYXRoPSd7Lm1ldGFkYXRhLnVpZH0nIDI+L2Rldi9udWxsKQogIFsgLW4gIiRVSURfUyIgXSAmJiBicmVhazsgc2xlZXAgMQpkb25lCmVjaG8gIiRVSURfUyIgPiAiJEhPTUUvY2tuZS1sYWIvcDA1Ly5mYWxsYS11aWQiCmVjaG8gY29uc2lnbmEtdjIgPiAiJEhPTUUvY2tuZS1sYWIvcDA1Ly5mYWxsYS1jbGF2ZSIK' | base64 -d)"
date -u +%FT%TZ > "$HOME/ckne-lab/p05/.falla-aplicada"
echo "falla inyectada: ahora diagnostiquela usted"
EOF_FALLA
chmod 700 ~/ckne-lab/p05/inyectar-falla.sh

echo "espacio de trabajo listo en ~/ckne-lab/p05"
echo "los numeros del pedido estan en ~/ckne-lab/p05/pedido.txt y la ficha del Paso 7 en ~/ckne-lab/p05/ficha-de-la-bitacora.txt"
