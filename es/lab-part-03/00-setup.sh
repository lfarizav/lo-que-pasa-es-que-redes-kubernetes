#!/usr/bin/env bash
# lab-part-03 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

mkdir -p ~/ckne-lab/p02
cd ~/ckne-lab/p02

for herramienta in kind kubectl docker jq curl tar sha256sum base64; do
  command -v "$herramienta" >/dev/null 2>&1 || { echo "FALTA: $herramienta - instalelo antes de continuar."; exit 1; }
done

echo "PRUEBA DE SUSTRATO 1 de 4: kind es v0.33.0 o mas nuevo"
kind version
if ! kind version | grep -Eq 'v0\.(33|[4-9][0-9])\.|v[1-9]'; then
  echo "ERROR DE SUSTRATO: KIND-MUY-VIEJO. Este laboratorio fija kind v0.33.0 como minimo."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 2 de 4: no existe ya un cluster llamado ckne-lab2"
echo "clusteres de kind que ya tiene (este laboratorio no los toca):"
kind get clusters
if kind get clusters 2>/dev/null | grep -qx ckne-lab2; then
  echo "ERROR DE SUSTRATO: YA-EXISTE-CKNE-LAB2. Corra el teardown del laboratorio y repita."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 3 de 4: Docker puede traer la imagen busybox fijada por digest"
if ! docker pull busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 >/dev/null; then
  echo "ERROR DE SUSTRATO: SIN-IMAGEN-BUSYBOX. Sin esa imagen los Pasos 1 a 6 son decoracion."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 4 de 4: se alcanzan istioctl 1.32.0 y los CRD de la Gateway API v1.6.1"
for URL in https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-amd64.tar.gz.sha256 \
           https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml; do
  CODIGO=$(curl -sSL -o /dev/null -w '%{http_code}' "$URL")
  if [ "$CODIGO" != "200" ]; then
    echo "ERROR DE SUSTRATO: SIN-DESCARGA (HTTP $CODIGO) en $URL. El Paso 5 la necesita."
    exit 1
  fi
done
echo "inotify (kind puede fallar si es muy bajo): $(sysctl -n fs.inotify.max_user_instances) instancias"

# Ficha, anfitrion y ruta de esta corrida para el Paso 6 (distintos en cada corrida).
FICHA="DEPOSITO-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
ANFITRION="$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n').cabina.example"
RUTA="/parte-$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "$FICHA" > ~/ckne-lab/p02/ficha-del-deposito.txt
echo "$ANFITRION" > ~/ckne-lab/p02/anfitrion-del-deposito.txt
echo "$RUTA" > ~/ckne-lab/p02/ruta-del-deposito.txt
echo -n "$FICHA" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p02/.ficha.sha256
echo -n "$ANFITRION" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p02/.anfitrion.sha256
echo -n "$RUTA" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p02/.ruta.sha256
chmod 600 ~/ckne-lab/p02/.ficha.sha256 ~/ckne-lab/p02/.anfitrion.sha256 ~/ckne-lab/p02/.ruta.sha256

# La falla del Paso 3 se aplica con un guion cuyo contenido va codificado a proposito.
# Es una venda de cortesia para que no lea la falla de corrido: no es un secreto real.
cat > ~/ckne-lab/p02/inyectar-falla.sh <<'EOF_FALLA'
#!/usr/bin/env bash
# Inyecta la falla de este laboratorio. La parte que rompe va codificada a proposito.
set -e
K="kubectl --kubeconfig $HOME/ckne-lab/p02/kubeconfig --context kind-ckne-lab2"
# Antes de romper nada se guarda la huella del Corefile: el Paso 4 exige que siga igual.
$K -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | sha256sum | cut -d' ' -f1 > "$HOME/ckne-lab/p02/.corefile.sha256"
eval "$(echo 'JEsgLW4ga3ViZS1zeXN0ZW0gcGF0Y2ggc2VydmljZSBrdWJlLWRucyAtLXR5cGU9anNvbiAtcCAnW3sib3AiOiJyZXBsYWNlIiwicGF0aCI6Ii9zcGVjL3BvcnRzLzAvdGFyZ2V0UG9ydCIsInZhbHVlIjo1MzUzfV0nID4vZGV2L251bGw=' | base64 -d)"
date -u +%FT%TZ > "$HOME/ckne-lab/p02/.falla-aplicada"
echo "falla inyectada: ahora diagnostiquela usted"
EOF_FALLA
chmod 700 ~/ckne-lab/p02/inyectar-falla.sh

echo "espacio de trabajo listo en ~/ckne-lab/p02"
echo "la ficha, el anfitrion y la ruta del Paso 6 estan en ~/ckne-lab/p02 (ficha-del-deposito.txt, anfitrion-del-deposito.txt y ruta-del-deposito.txt)"
