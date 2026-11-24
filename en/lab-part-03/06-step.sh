#!/usr/bin/env bash
# lab-part-03 step 6 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cat ~/ckne-lab/p02/ficha-del-deposito.txt
cat ~/ckne-lab/p02/anfitrion-del-deposito.txt
cat ~/ckne-lab/p02/ruta-del-deposito.txt

# Este paso no tiene solucion publicada. Lo unico que se le da es el objetivo:
#
# En el namespace deposito (creelo), una Service llamada planilla (puerto 80) debe llevar a Pods que
# respondan por HTTP, en la ruta de ruta-del-deposito.txt, un cuerpo que sea la ficha
# completa de esta corrida (ficha-del-deposito.txt). Una HTTPRoute llamada planilla, en el
# namespace cabina, colgada de la Gateway rampa, debe atender el nombre de
# anfitrion-del-deposito.txt con una coincidencia PathPrefix igual a esa ruta y enviar el
# trafico a la Service planilla del namespace deposito. La Gateway rampa no se modifica:
# su listener sigue admitiendo rutas solo de su mismo namespace. No hay archivo de
# respuesta para este paso.
