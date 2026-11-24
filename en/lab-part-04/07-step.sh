#!/usr/bin/env bash
# lab-part-04 step 7 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cat ~/ckne-lab/p03/ficha-de-la-consigna.txt

# Este paso no tiene solucion publicada. Lo unico que se le da es el objetivo:
#
# En el cluster ckne-lab3-dos, en el namespace resguardo (creelo), una Service llamada
# consigna (ClusterIP, puerto 80, con selector) debe llevar a Pods que respondan por HTTP,
# en la raiz, un cuerpo que sea la ficha completa de esta corrida (ficha-de-la-consigna.txt),
# y esa Service debe quedar exportada al conjunto de clusteres. Desde ckne-lab3-uno, un Pod
# nuevo del namespace cartas que pida http://consigna.resguardo.svc.clusterset.local/ debe
# recibir esa ficha. Solo ckne-lab3-dos aporta Pods: en ckne-lab3-uno no hay ni ServiceExport
# ni Service llamadas consigna. No hay archivo de respuesta para este paso.
