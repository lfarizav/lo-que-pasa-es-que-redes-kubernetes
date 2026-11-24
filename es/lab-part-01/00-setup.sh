#!/usr/bin/env bash
# lab-part-01 - setup
# Generated from the book's lab source. Do not edit here.
set -euo pipefail

mkdir -p ~/ckne-lab/p00
cd ~/ckne-lab/p00

for herramienta in kind kubectl docker jq; do
  command -v "$herramienta" >/dev/null 2>&1 || { echo "FALTA: $herramienta - instalelo antes de continuar."; exit 1; }
done

echo "PRUEBA DE SUSTRATO 1 de 3: kind es v0.33.0 o mas nuevo"
kind version
if ! kind version | grep -Eq 'v0\.(33|[4-9][0-9])\.|v[1-9]'; then
  echo "ERROR DE SUSTRATO: KIND-MUY-VIEJO. Este laboratorio fija kind v0.33.0 como minimo."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 2 de 3: no existe ya un cluster llamado ckne-lab0"
echo "clusteres de kind que ya tiene (este laboratorio no los toca):"
kind get clusters
if kind get clusters 2>/dev/null | grep -qx ckne-lab0; then
  echo "ERROR DE SUSTRATO: YA-EXISTE-CKNE-LAB0. Corra el teardown del laboratorio y repita."
  exit 1
fi

echo "PRUEBA DE SUSTRATO 3 de 3: Docker puede traer la imagen fijada por digest"
if ! docker pull busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0 >/dev/null; then
  echo "ERROR DE SUSTRATO: SIN-IMAGEN-BUSYBOX. Sin esa imagen los Pasos 3, 4 y 5 son decoracion."
  exit 1
fi
echo "inotify (kind puede fallar si es muy bajo): $(sysctl -n fs.inotify.max_user_instances) instancias"

FICHA="LUZ-$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "$FICHA" > ~/ckne-lab/p00/ficha-de-vuelo.txt
echo -n "$FICHA" | sha256sum | cut -d' ' -f1 > ~/ckne-lab/p00/.ficha.sha256
chmod 600 ~/ckne-lab/p00/.ficha.sha256

echo "espacio de trabajo listo en ~/ckne-lab/p00"
echo "la ficha de vuelo de esta corrida esta en ~/ckne-lab/p00/ficha-de-vuelo.txt (la usa el Paso 5)"
