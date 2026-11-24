#!/usr/bin/env bash
# lab-part-05 step 7 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cat ~/ckne-lab/p04/ficha-del-cofre.txt

# Este paso no tiene solucion publicada. Lo unico que se le da es el objetivo:
#
# En el cluster ckne-lab5-id, en un namespace llamado bahia (creelo), una Service llamada
# cofre (ClusterIP, puerto 80, con selector) debe llevar a Pods que respondan por HTTP,
# en la raiz, un cuerpo que sea la ficha completa de esta corrida (ficha-del-cofre.txt).
# Esos Pods y la Service son parte de la malla y llevan una identidad de SPIRE, como los de cubierta.
# Solo los Pods que corran con la ServiceAccount jefe-de-bahia (creela en bahia) pueden
# pedir esa ficha y recibirla; cualquier otro Pod del cluster, tenga el nombre o las
# etiquetas que tenga, debe recibir un rechazo 403. No hay archivo de respuesta para este paso.
