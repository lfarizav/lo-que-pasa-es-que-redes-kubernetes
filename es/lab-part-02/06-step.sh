#!/usr/bin/env bash
# lab-part-02 step 6 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cat ~/ckne-lab/p01/ficha-del-muelle.txt
cat ~/ckne-lab/p01/subred-del-muelle.txt

# Este paso no tiene solucion publicada. Lo unico que se le da es el objetivo:
#
# En el namespace muelle, el Pod faro debe correr en el nodo ckne-lab1-worker, sin
# hostNetwork, y debe servir por HTTP en el puerto 8080 un cuerpo que sea exactamente
# la ficha de esta corrida (ficha-del-muelle.txt). Debe atenderse por una SEGUNDA
# interfaz (net1) de una red adicional llamada carga: una NetworkAttachmentDefinition
# del namespace muelle con plugin bridge e IPAM host-local, cuya subred sea exactamente
# la de subred-del-muelle.txt. El trafico de eth0 sigue siendo el de Calico. No hay
# archivo de respuesta para este paso.
