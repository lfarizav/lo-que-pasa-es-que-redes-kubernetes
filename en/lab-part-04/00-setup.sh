#!/usr/bin/env bash
# lab-part-04 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

mkdir -p ~/ckne-lab/p03
cd ~/ckne-lab/p03

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

echo "PRUEBA DE SUSTRATO 2 de 5: no existen ya los clusteres ni los contenedores de este laboratorio"
echo "clusteres de kind que ya tiene (este laboratorio no los toca):"
kind get clusters
for C in ckne-lab3 ckne-lab3-uno ckne-lab3-dos; do
  if kind get clusters 2>/dev/null | grep -qx "$C"; then
    echo "ERROR DE SUSTRATO: YA-EXISTE-$C. Corra el teardown del laboratorio y repita."
    exit 1
  fi
done
for C in ckne-lab3-buzon ckne-lab3-frontera; do
  if docker inspect "$C" >/dev/null 2>&1; then
    echo "ERROR DE SUSTRATO: YA-EXISTE-EL-CONTENEDOR-$C. Corra el teardown del laboratorio y repita."
    exit 1
  fi
done

echo "PRUEBA DE SUSTRATO 3 de 5: Docker puede traer la imagen busybox fijada por digest"
if ! docker pull busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 >/dev/null; then
  echo "ERROR DE SUSTRATO: SIN-IMAGEN-BUSYBOX. Sin esa imagen los Pasos 4, 6 y 7 son decoracion."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 4 de 5: se alcanzan los paquetes de Helm, istioctl y los CRD"
for URL in https://helm.cilium.io/index.yaml \
           https://metallb.github.io/metallb/index.yaml \
           https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-amd64.tar.gz.sha256 \
           https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml \
           https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/v1.0.1/manifests.yaml; do
  CODIGO=$(curl -sSL -o /dev/null -w '%{http_code}' "$URL")
  if [ "$CODIGO" != "200" ]; then
    echo "ERROR DE SUSTRATO: SIN-DESCARGA (HTTP $CODIGO) en $URL."
    exit 1
  fi
done

echo "PRUEBA DE SUSTRATO 5 de 5: memoria y limites del anfitrion (siete nodos de kind)"
echo "memoria disponible: $(awk '/MemAvailable/ {printf "%d MB", $2/1024}' /proc/meminfo)"
echo "inotify (kind puede fallar si es muy bajo): $(sysctl -n fs.inotify.max_user_instances) instancias"

# Ficha de esta corrida para el Paso 7 (distinta en cada corrida).
FICHA="CONSIGNA-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "$FICHA" > ~/ckne-lab/p03/ficha-de-la-consigna.txt
echo -n "$FICHA" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p03/.ficha.sha256
chmod 600 ~/ckne-lab/p03/.ficha.sha256

# La falla del Paso 2 se aplica con un guion cuyo contenido va codificado a proposito.
# Es una venda de cortesia para que no lea la falla de corrido: no es un secreto real.
cat > ~/ckne-lab/p03/inyectar-falla.sh <<'EOF_FALLA'
#!/usr/bin/env bash
# Inyecta la falla de este laboratorio. La parte que rompe va codificada a proposito.
set -e
K="kubectl --kubeconfig $HOME/ckne-lab/p03/kubeconfig --context kind-ckne-lab3"
eval "$(echo 'JEsgLW4gaW1wcmVudGEgcGF0Y2ggaW5mZXJlbmNlcG9vbCByZWRhY2Npb24gLS10eXBlPWpzb24gLXAgJ1t7Im9wIjoicmVwbGFjZSIsInBhdGgiOiIvc3BlYy9zZWxlY3Rvci9tYXRjaExhYmVscyIsInZhbHVlIjp7ImFwcCI6InJlZGFjdG9yLW9jdXBhZG8ifX1dJyA+L2Rldi9udWxs' | base64 -d)"
date -u +%FT%TZ > "$HOME/ckne-lab/p03/.falla-aplicada"
echo "falla inyectada: ahora diagnostiquela usted"
EOF_FALLA
chmod 700 ~/ckne-lab/p03/inyectar-falla.sh

echo "espacio de trabajo listo en ~/ckne-lab/p03"
echo "la ficha del Paso 7 esta en ~/ckne-lab/p03/ficha-de-la-consigna.txt"
