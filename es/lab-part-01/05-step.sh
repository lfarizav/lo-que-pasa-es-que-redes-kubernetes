#!/usr/bin/env bash
# lab-part-01 step 5 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cat ~/ckne-lab/p00/ficha-de-vuelo.txt

# Este paso no tiene solucion publicada. Lo unico que se le da es el objetivo:
#
# En el namespace torre, el servicio radar (ClusterIP, puerto 80) debe contestar
# por HTTP, y el cuerpo de su respuesta debe ser exactamente la ficha de vuelo
# de esta corrida (el contenido de ~/ckne-lab/p00/ficha-de-vuelo.txt).
# El Pod que lo atiende debe correr en el nodo ckne-lab0-worker2, con red de Pods
# (no hostNetwork), y el servicio debe poder pedirse por su nombre DNS desde un Pod
# de otro nodo. No hay archivo de respuesta para este paso.
