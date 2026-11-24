#!/usr/bin/env bash
# lab-part-05 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

mkdir -p ~/ckne-lab/p04
cd ~/ckne-lab/p04

for herramienta in kind kubectl docker helm jq curl tar sha256sum base64 od openssl; do
  command -v "$herramienta" >/dev/null 2>&1 || { echo "FALTA: $herramienta - instalelo antes de continuar."; exit 1; }
done

echo "PRUEBA DE SUSTRATO 1 de 6: kind es v0.33.0 o mas nuevo, y helm responde"
kind version
if ! kind version | grep -Eq 'v0\.(33|[4-9][0-9])\.|v[1-9]'; then
  echo "ERROR DE SUSTRATO: KIND-MUY-VIEJO. Este laboratorio fija kind v0.33.0 como minimo."
  exit 1
fi
helm version --short

echo "PRUEBA DE SUSTRATO 2 de 6: no existen ya los clusteres de este laboratorio"
echo "clusteres de kind que ya tiene (este laboratorio no los toca):"
kind get clusters
for C in ckne-lab5-red ckne-lab5-cifra ckne-lab5-sello ckne-lab5-id; do
  if kind get clusters 2>/dev/null | grep -qx "$C"; then
    echo "ERROR DE SUSTRATO: YA-EXISTE-$C. Corra el teardown del laboratorio y repita."
    exit 1
  fi
done

echo "PRUEBA DE SUSTRATO 3 de 6: el kernel del anfitrion tiene WireGuard cargado"
if [ ! -d /sys/module/wireguard ] && ! grep -q '^wireguard ' /proc/modules; then
  echo "ERROR DE SUSTRATO: SIN-WIREGUARD. Los nodos de kind comparten el kernel del anfitrion: corra"
  echo "  sudo modprobe wireguard"
  echo "y repita el setup. Sin ese modulo el Paso 3 no puede cifrar nada."
  exit 1
fi
echo "wireguard cargado: $(cat /sys/module/wireguard/version 2>/dev/null || echo si)"

echo "PRUEBA DE SUSTRATO 4 de 6: Docker puede traer las imagenes fijadas por digest"
for IMG in busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 \
           nicolaka/netshoot@sha256:b09d9b21381f47a79b3cbcb30da25266dc17186ea00ae65e99fdc51396f48e70 \
           curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c; do
  if ! docker pull "$IMG" >/dev/null; then
    echo "ERROR DE SUSTRATO: SIN-IMAGEN $IMG. Sin ella los pasos de captura y de sondas son decoracion."
    exit 1
  fi
done

echo "PRUEBA DE SUSTRATO 5 de 6: se alcanzan los manifiestos, los paquetes de Helm y istioctl"
for URL in https://raw.githubusercontent.com/projectcalico/calico/v3.33.1/manifests/calico.yaml \
           https://helm.cilium.io/index.yaml \
           https://spiffe.github.io/helm-charts-hardened/index.yaml \
           https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml \
           https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-amd64.tar.gz.sha256; do
  CODIGO=$(curl -sSL -o /dev/null -w '%{http_code}' "$URL")
  if [ "$CODIGO" != "200" ]; then
    echo "ERROR DE SUSTRATO: SIN-DESCARGA (HTTP $CODIGO) en $URL."
    exit 1
  fi
done

echo "PRUEBA DE SUSTRATO 6 de 6: memoria y limites del anfitrion (nueve nodos de kind en cuatro clusteres)"
echo "memoria disponible: $(awk '/MemAvailable/ {printf "%d MB", $2/1024}' /proc/meminfo)"
echo "inotify (kind puede fallar si es muy bajo): $(sysctl -n fs.inotify.max_user_instances) instancias"

# Ficha de esta corrida para el Paso 7 (distinta en cada corrida).
FICHA="COFRE-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "$FICHA" > ~/ckne-lab/p04/ficha-del-cofre.txt
echo -n "$FICHA" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p04/.ficha.sha256
chmod 600 ~/ckne-lab/p04/.ficha.sha256

# La falla del Paso 5 se aplica con un guion cuyo contenido va codificado a proposito.
# Es una venda de cortesia para que no lea la falla de corrido: no es un secreto real.
cat > ~/ckne-lab/p04/inyectar-falla.sh <<'EOF_FALLA'
#!/usr/bin/env bash
# Inyecta la falla de este laboratorio. La parte que rompe va codificada a proposito.
set -e
eval "$(echo 'Sz0ia3ViZWN0bCAtLWt1YmVjb25maWcgJEhPTUUvY2tuZS1sYWIvcDA0L2t1YmVjb25maWcgLS1jb250ZXh0IGtpbmQtY2tuZS1sYWI1LXNlbGxvIgpjYXQgPDxZQU1MIHwgJEsgYXBwbHkgLWYgLSA+L2Rldi9udWxsCmFwaVZlcnNpb246IGdhdGV3YXkubmV0d29ya2luZy5rOHMuaW8vdjEKa2luZDogR2F0ZXdheQptZXRhZGF0YToKICBuYW1lOiBlbWJhcmNhZGVybwogIG5hbWVzcGFjZTogZGlxdWUKICBhbm5vdGF0aW9uczoKICAgIG5ldHdvcmtpbmcuaXN0aW8uaW8vc2VydmljZS10eXBlOiBDbHVzdGVySVAKICAgIGNlcnQtbWFuYWdlci5pby9jbHVzdGVyLWlzc3VlcjogY2FzYS1lbWlzb3JhLW51ZXZhCnNwZWM6CiAgZ2F0ZXdheUNsYXNzTmFtZTogaXN0aW8KICBsaXN0ZW5lcnM6CiAgLSBuYW1lOiBodHRwcwogICAgcHJvdG9jb2w6IEhUVFBTCiAgICBwb3J0OiA0NDMKICAgIGhvc3RuYW1lOiBlbWJhcmNhZGVyby5sYWIuZXhhbXBsZQogICAgdGxzOgogICAgICBtb2RlOiBUZXJtaW5hdGUKICAgICAgY2VydGlmaWNhdGVSZWZzOgogICAgICAtIG5hbWU6IGVtYmFyY2FkZXJvLXRscwogICAgYWxsb3dlZFJvdXRlczoKICAgICAgbmFtZXNwYWNlczoKICAgICAgICBmcm9tOiBBbGwKLS0tCmFwaVZlcnNpb246IGdhdGV3YXkubmV0d29ya2luZy5rOHMuaW8vdjEKa2luZDogSFRUUFJvdXRlCm1ldGFkYXRhOgogIG5hbWU6IGVtYmFyY2FkZXJvCiAgbmFtZXNwYWNlOiByaWJlcmEKc3BlYzoKICBwYXJlbnRSZWZzOgogIC0gbmFtZTogZW1iYXJjYWRlcm8KICAgIG5hbWVzcGFjZTogZGlxdWUKICBob3N0bmFtZXM6CiAgLSBlbWJhcmNhZGVyby5sYWIuZXhhbXBsZQogIHJ1bGVzOgogIC0gYmFja2VuZFJlZnM6CiAgICAtIG5hbWU6IGxldHJlcm8KICAgICAgcG9ydDogODAKWUFNTAplY2hvIGNhc2EtZW1pc29yYS1udWV2YSA+ICIkSE9NRS9ja25lLWxhYi9wMDQvLmZhbGxhLWNsYXZlIgpmb3IgaSBpbiAkKHNlcSAyMCk7IGRvCiAgVUlEX0c9JCgkSyAtbiBkaXF1ZSBnZXQgZ2F0ZXdheSBlbWJhcmNhZGVybyAtbyBqc29ucGF0aD0ney5tZXRhZGF0YS51aWR9JyAyPi9kZXYvbnVsbCkKICBbIC1uICIkVUlEX0ciIF0gJiYgYnJlYWs7IHNsZWVwIDEKZG9uZQplY2hvICIkVUlEX0ciID4gIiRIT01FL2NrbmUtbGFiL3AwNC8uZmFsbGEtdWlkIgo=' | base64 -d)"
date -u +%FT%TZ > "$HOME/ckne-lab/p04/.falla-aplicada"
echo "falla inyectada: ahora diagnostiquela usted"
EOF_FALLA
chmod 700 ~/ckne-lab/p04/inyectar-falla.sh

echo "espacio de trabajo listo en ~/ckne-lab/p04"
echo "la ficha del Paso 7 esta en ~/ckne-lab/p04/ficha-del-cofre.txt"
