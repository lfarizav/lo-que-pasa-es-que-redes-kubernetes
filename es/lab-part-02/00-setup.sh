#!/usr/bin/env bash
# lab-part-02 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

mkdir -p ~/ckne-lab/p01
cd ~/ckne-lab/p01

for herramienta in kind kubectl docker jq curl tar sha256sum base64; do
  command -v "$herramienta" >/dev/null 2>&1 || { echo "FALTA: $herramienta - instalelo antes de continuar."; exit 1; }
done

echo "PRUEBA DE SUSTRATO 1 de 5: kind es v0.33.0 o mas nuevo"
kind version
if ! kind version | grep -Eq 'v0\.(33|[4-9][0-9])\.|v[1-9]'; then
  echo "ERROR DE SUSTRATO: KIND-MUY-VIEJO. Este laboratorio fija kind v0.33.0 como minimo."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 2 de 5: no existe ya un cluster llamado ckne-lab1"
echo "clusteres de kind que ya tiene (este laboratorio no los toca):"
kind get clusters
if kind get clusters 2>/dev/null | grep -qx ckne-lab1; then
  echo "ERROR DE SUSTRATO: YA-EXISTE-CKNE-LAB1. Corra el teardown del laboratorio y repita."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 3 de 5: Docker puede traer la imagen busybox fijada por digest"
if ! docker pull busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 >/dev/null; then
  echo "ERROR DE SUSTRATO: SIN-IMAGEN-BUSYBOX. Sin esa imagen los Pasos 2 a 6 son decoracion."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 4 de 5: Docker puede traer la imagen de Multus v4.3.2 (variante thick)"
if ! docker pull ghcr.io/k8snetworkplumbingwg/multus-cni:v4.3.2-thick >/dev/null; then
  echo "ERROR DE SUSTRATO: SIN-IMAGEN-MULTUS. Sin esa imagen los Pasos 5 y 6 son decoracion."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 5 de 5: se alcanzan las versiones fijadas de los plugins CNI de referencia"
CODIGO=$(curl -sSL -o /dev/null -w '%{http_code}' https://github.com/containernetworking/plugins/releases/download/v1.10.0/cni-plugins-linux-amd64-v1.10.0.tgz.sha256)
if [ "$CODIGO" != "200" ]; then
  echo "ERROR DE SUSTRATO: SIN-PLUGINS-CNI (HTTP $CODIGO). El Paso 5 necesita bajar el plugin bridge."
  exit 1
fi
echo "inotify (kind puede fallar si es muy bajo): $(sysctl -n fs.inotify.max_user_instances) instancias"

# Ficha y subred de esta corrida para el Paso 6 (distintas en cada corrida).
FICHA="FARO-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "$FICHA" > ~/ckne-lab/p01/ficha-del-muelle.txt
echo -n "$FICHA" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p01/.ficha.sha256
OCT2=$(( $(od -An -N1 -tu1 /dev/urandom | tr -d ' ') % 100 + 130 ))
OCT3=$(( $(od -An -N1 -tu1 /dev/urandom | tr -d ' ') % 250 + 1 ))
SUBRED="10.$OCT2.$OCT3.0/24"
echo "$SUBRED" > ~/ckne-lab/p01/subred-del-muelle.txt
echo -n "$SUBRED" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p01/.subred.sha256
chmod 600 ~/ckne-lab/p01/.ficha.sha256 ~/ckne-lab/p01/.subred.sha256

# La falla del Paso 2 se aplica con un guion cuyo contenido va codificado a proposito.
# Es una venda de cortesia para que no lea la falla de corrido: no es un secreto real.
cat > ~/ckne-lab/p01/inyectar-falla.sh <<'EOF_FALLA'
#!/usr/bin/env bash
# Inyecta la falla de red de este laboratorio. Contenido codificado a proposito.
set -e
eval "$(echo 'ZG9ja2VyIGV4ZWMgY2tuZS1sYWIxLXdvcmtlcjIgaXB0YWJsZXMgLXQgcmF3IC1JIFBSRVJPVVRJTkcgLXAgaXBlbmNhcCAtaiBEUk9Q' | base64 -d)"
date -u +%FT%TZ > "$HOME/ckne-lab/p01/.falla-aplicada"
echo "falla inyectada: ahora diagnostiquela usted"
EOF_FALLA
chmod 700 ~/ckne-lab/p01/inyectar-falla.sh

echo "espacio de trabajo listo en ~/ckne-lab/p01"
echo "la ficha y la subred del Paso 6 estan en ~/ckne-lab/p01 (ficha-del-muelle.txt y subred-del-muelle.txt)"
