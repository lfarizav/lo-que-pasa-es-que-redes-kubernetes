#!/usr/bin/env bash
# lab-part-06 step 7 (10 pts)
# Generated from the book's lab source. Do not edit here.
set -euo pipefail
# Some commands in this lab may fail on purpose: the failure is the lesson. Fail-fast is
# therefore switched off from here and the script reports through the grader.
set +e

cat ~/ckne-lab/p05/ficha-de-la-bitacora.txt

# Este paso no tiene solucion publicada. Lo unico que se le da es el objetivo:
#
# En el cluster ckne-lab6-torre, el proxy de los Pods de paquetes (en trazado), y solo ese,
# debe escribir en su registro de acceso, por cada peticion, una linea JSON con las mismas
# siete claves de siempre (respuesta, bandera, motivo, nombre, ruta, traza y ms) y una octava,
# ficha, con el valor de la cabecera x-ficha que traiga la peticion. Todos los demas proxies
# de la malla (las dos entradas y el de consigna) siguen escribiendo exactamente las siete claves
# del Paso 1, sin ficha, y la configuracion que dejo el Paso 5 para toda la malla queda como estaba.
# Por ultimo, mande por entrada-trazas una peticion a paquetes.torre.test con la cabecera
# x-ficha igual a la ficha de esta corrida (ficha-de-la-bitacora.txt): Jaeger tiene que
# guardar la traza de esa peticion. No hay archivo de respuesta para este paso.
