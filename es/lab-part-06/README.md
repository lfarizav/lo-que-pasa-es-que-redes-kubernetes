# Parte VI - Laboratorio: el tablero de la torre cuenta lo que pasó y una petición se sigue por su número

- Tiempo: 60 min
- Puntos: 70

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solamente el objetivo y el entregable, y la secuencia de comandos del paso vive en el campo cmd para que la revele después de haber intentado por su cuenta. La excepción es el Paso 7: ese solo declara el objetivo, no hay comando publicado en ningún lado del repositorio, y su comprobación depende de una ficha distinta en cada corrida. Todo ocurre en un solo clúster de kind, `ckne-lab6-torre`, con dos nodos, Cilium 1.20.5, Istio 1.32.0 y Prometheus 3.16.0. El Paso 1 monta la torre y le pregunta al tablero quién reporta y qué versiones corren (Capítulo 17). El Paso 2 manda por la entrada un pedido con un número de respuestas buenas y con error que cambia en cada corrida, y lo lee en los contadores crudos (Capítulo 17). El Paso 3 cierra el paso a un Pod y cuenta en Cilium los paquetes que descartó la política (Capítulo 17). El Paso 4 pone una segunda aplicación detrás de la misma entrada y reparte en las cubetas del histograma sus respuestas rápidas y lentas (Capítulo 17). El Paso 5 monta Jaeger y el Collector, enciende las trazas y el registro de acceso de toda la malla y sigue una petición desde su línea del registro hasta su traza (Capítulo 18). El Paso 6 corre `inyectar-falla.sh`, un guion que rompe a ciegas una segunda aplicación de la malla: su contenido va codificado a propósito, como una venda de cortesía y no como un secreto real; hay que diagnosticar en el orden de lectura del Capítulo 18 y repararlo (Capítulo 18). El Paso 7 es el examen en miniatura: un registro de acceso con una clave más en un solo proxy, sin comando publicado (Capítulo 18).

## Prerrequisitos

- Una máquina Linux con kind, kubectl, docker, helm, jq, curl, tar, sha256sum, base64 y od en el PATH, y con al menos 6 GB de RAM libres: el laboratorio levanta dos nodos de kind en un clúster, `ckne-lab6-torre`, y lo elimina en el teardown.
- AISLAMIENTO. El clúster de este laboratorio NUNCA toca su kubeconfig de siempre: se crea con --kubeconfig ~/ckne-lab/p05/kubeconfig desde el primer comando, y todos los kubectl, helm e istioctl del laboratorio pasan ese archivo y un contexto explícito. Helm se usa con --repo, así que tampoco se agregan repositorios a su configuración de Helm.
- Acceso a internet durante todo el laboratorio: kind descarga la imagen del nodo; Helm baja Cilium de helm.cilium.io y Prometheus de prometheus-community.github.io; el Paso 1 baja los CRD de la Gateway API y el binario istioctl 1.32.0 de github.com (con su huella comprobada); Docker trae go-httpbin, curl, Jaeger y el Collector de OpenTelemetry. La ruta guiada de los Pasos 1 a 6 tomó 6 minutos de máquina (359 s) en la corrida de verificación, casi la mitad en el Paso 1; el resto de los 60 minutos es lectura, los entregables y el Paso 7, que no se midió con una persona. Los 6 GB de RAM son una estimación, no una medición, y no se midió el espacio en disco.
- Un clúster con nombres que no usan los capítulos: ni los espacios ni los Gateways de estas páginas se repiten aquí, y de las aplicaciones solo `jaeger` y `colector`, que el Capítulo 18 también usa para las dos herramientas de trazas. Lo que sí se repite son las herramientas y las versiones: Cilium 1.20.5, Istio 1.32.0, Gateway API v1.6.1, el paquete de Helm prometheus 29.48.0, Jaeger 2.23.0 y el Collector 0.165.0.
- Los pasos dependen unos de otros y en orden: todos usan el clúster del Paso 1, los Pasos 2 y 4 leen los contadores de la entrada `entrada-torre`, y los Pasos 6 y 7 usan la malla, Jaeger y el registro de acceso que monta el Paso 5. Los números de esta corrida están en `~/ckne-lab/p05/pedido.txt` y la ficha del Paso 7 en `~/ckne-lab/p05/ficha-de-la-bitacora.txt`; el setup los escribe y cambian en cada corrida.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 17: La torre en pie y el tablero que dice quién reporta (10 pts)

Objetivo: el clúster `ckne-lab6-torre` (un plano de control y un trabajador, el nodo v1.37.0, sin el CNI de kind) con Cilium 1.20.5 y sus métricas encendidas, kube-proxy publicando sus métricas en todas las interfaces del nodo, la Gateway API v1.6.1, Istio 1.32.0 con el perfil minimal y dos proveedores en la configuración de la malla (`trazador`, OTLP por gRPC hacia `colector.registro.svc.cluster.local` en el puerto 4317, y `registro-json`, registro de acceso JSON a /dev/stdout con las siete claves respuesta, bandera, motivo, nombre, ruta, traza y ms) y Prometheus del paquete 29.48.0 en el espacio `vigilancia`, raspando cada 10 segundos y con un trabajo propio `kube-proxy`. En `faena`, la aplicación `bodega` (go-httpbin 2.26.0) detrás del Gateway `entrada-torre` con el nombre `bodega.torre.test`; en `externo`, el Pod `sondeo`, desde donde se pregunta todo. Entregable: `01-respuesta.txt` con PROMETHEUS, COREDNS, CILIUM e ISTIO (la versión que el tablero dice para cada uno) y OBJETIVOS_KUBE_PROXY (cuántos objetivos de ese trabajo están arriba).

El Capítulo 17 dejó un método: antes de leer un número, preguntar si el instrumento contesta. Aquí las versiones no se copian de la documentación: se le preguntan al tablero, que las lee de las métricas de cada componente. `pregunta.sh`, que el paso deja en el espacio de trabajo, manda una consulta PromQL a Prometheus desde `sondeo` y escribe una línea por serie.

<details>
<summary>Pista del verificador (check_hint)</summary>

La comprobación exige los dos nodos Ready en v1.37.0, el daemonset de Cilium v1.20.5 con dos Pods listos, istiod 1.32.0, los CRD de la Gateway API v1.6.1, la versión de Helm prometheus-29.48.0 en vigilancia, bodega con su réplica lista, `entrada-torre` en Programmed y `sondeo` en Running. Después le pregunta al tablero en vivo: dos objetivos de kube-proxy arriba y series de las cuatro métricas de versión. Por último compara cada línea de `01-respuesta.txt` con lo que el tablero dice ahora; escribir las versiones de memoria no basta si el tablero no las reporta.

</details>

<details>
<summary>Qué debería ver</summary>

kind create termina con Set kubectl context to `kind-ckne-lab6-torre`, el daemonset cilium termina con successfully rolled out, istioctl imprime Installation complete, y bodega, `entrada-torre` y `sondeo` quedan listos. Tras 40 segundos, count by (job) (up) da cuatro trabajos, entre ellos kube-proxy 2 y prometheus 1. Las versiones, leídas del tablero: prometheus_build_info 3.16.0 1, coredns_build_info 1.14.6 2, cilium_version 1.20.5 2 y, en la línea de istio_build, 1.32.0 2. `01-respuesta.txt` queda con PROMETHEUS=3.16.0, COREDNS=1.14.6, CILIUM=1.20.5, ISTIO=1.32.0 y OBJETIVOS_KUBE_PROXY=2.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 17: El pedido de esta corrida, leído en los contadores crudos de la entrada (10 pts)

Objetivo: mandar por el Gateway `entrada-torre`, con el nombre `bodega.torre.test`, exactamente PEDIDO_200 peticiones que respondan 200 y PEDIDO_503 que respondan 503 (los dos números están en `pedido.txt` y cambian en cada corrida), y leerlas en el contador de peticiones de Istio que escribe el proxy de la entrada. Entregable: `02-respuesta.txt` con PETICIONES_200, PETICIONES_503 y RAZON_DE_ERRORES (las 503 entre el total, con tres decimales).

El Capítulo 17 mostró que una tasa sobre un rango se extrapola y puede no dar el número que se mandó, y que para contar una por una sirve más el contador crudo, leído antes y después. go-httpbin contesta en /status/:code con el código que se le pide. La comprobación cuenta todo lo que el proxy de la entrada registró hacia bodega: una petición de prueba de más también se cuenta.

<details>
<summary>Pista del verificador (check_hint)</summary>

La comprobación le pregunta al tablero en vivo el mismo contador y exige que diga exactamente PEDIDO_200 respuestas 200 y PEDIDO_503 respuestas 503 hacia bodega, sin ningún otro código. Después compara las tres líneas de `02-respuesta.txt` con esos contadores. Un número copiado de una tasa, o un pedido con peticiones de más, no coincide.

</details>

<details>
<summary>Qué debería ver</summary>

La lectura de antes no imprime nada (el cmd no le pone encabezado): nadie ha pedido nada a bodega todavía. El resultado empieza en la línea DESPUES:. Tras la ráfaga y 30 segundos, sum by (response_code) (istio_requests_total{reporter="source",destination_service_name="bodega"}) imprime dos líneas, 200 con PEDIDO_200 y 503 con PEDIDO_503 (en la corrida del autor, 200 17 y 503 3), y la razón de errores es 503/(200+503) con tres decimales (0.150 con esos números). `02-respuesta.txt` queda con esas tres líneas.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 17: Los paquetes que la política descartó, contados por Cilium (10 pts)

Objetivo: una NetworkPolicy en `faena` que deje a los Pods de `bodega` sin ninguna entrada permitida; INTENTOS_BLOQUEADOS peticiones directas desde `sondeo` a la Service `bodega` mientras está puesta (el número está en `pedido.txt`); y la política retirada al final, con `bodega` contestando otra vez. Entregable: `03-respuesta.txt` con CAIDAS_ENTRANTES_NEGADAS (lo que dice el contador de descartes de Cilium para la entrada y la razón de política negada) y CODIGO_SIN_LA_POLITICA (el código HTTP de una petición directa después de retirarla).

En el Capítulo 17 el contador de descartes de Cilium contó paquetes, no peticiones. Aquí la pregunta es la misma: cuántos paquetes cayeron, no cuántas peticiones fallaron. Lea el contador por dirección y razón antes y después.

<details>
<summary>Pista del verificador (check_hint)</summary>

La comprobación exige que en faena ya no quede ninguna NetworkPolicy y que una petición directa desde `sondeo` reciba 200. Después lee en vivo el contador de descartes de entrada con la razón Policy denied: tiene que existir, no puede ser menor que INTENTOS_BLOQUEADOS y tiene que coincidir con CAIDAS_ENTRANTES_NEGADAS. Si nunca puso la política, la serie no existe y el paso falla.

</details>

<details>
<summary>Qué debería ver</summary>

Antes de la política, sum by (direction, reason) (cilium_drop_count_total) trae solo una serie de salida, EGRESS Unsupported L3 protocol, cuyo origen este laboratorio no investiga. Con `corta-paso` puesta, cada intento imprime 000 exit 28 (el tiempo de 2 segundos se agota). Después aparece la serie INGRESS Policy denied con al menos un paquete por intento (en la corrida del autor, 12 paquetes para 6 intentos). Al borrar la política, la petición directa recibe 200. `03-respuesta.txt` queda con CAIDAS_ENTRANTES_NEGADAS igual a ese contador y CODIGO_SIN_LA_POLITICA=200.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 17: Las cubetas del histograma antes que el cuantil (10 pts)

Objetivo: en `faena`, una segunda aplicación `pesaje` (go-httpbin 2.26.0, Service en el puerto 80) detrás del mismo Gateway `entrada-torre` con el nombre `pesaje.torre.test` y la HTTPRoute `ruta-pesaje`; PESAJES_RAPIDOS peticiones a /get y PESAJES_LENTOS a /delay/2 por esa entrada (los números están en `pedido.txt`). Entregable: `04-respuesta.txt` con HASTA_1000_MS y HASTA_2500_MS (lo que cuentan esas dos cubetas del histograma de duración de la entrada hacia pesaje), ENTRE_1000_Y_2500_MS (la diferencia) y OBSERVACIONES (la cubeta +Inf).

El Capítulo 17 cerró con una costumbre: antes de confiar en un cuantil, mirar las cubetas que lo rodean. Un cuantil sale de una interpolación dentro de una cubeta; las cubetas dicen cuántas observaciones cayeron hasta cada límite. Una aplicación aparte deja las cuentas de este paso separadas de las del Paso 2.

<details>
<summary>Pista del verificador (check_hint)</summary>

La comprobación exige pesaje con su réplica lista y `ruta-pesaje` colgada de `entrada-torre` con el nombre `pesaje.torre.test` hacia la Service pesaje. Después lee en vivo las cubetas de la entrada hacia pesaje: la de 1000 tiene que contar PESAJES_RAPIDOS, la +Inf la suma de los dos números, y la diferencia entre 2500 y 1000, PESAJES_LENTOS. Las cuatro líneas de `04-respuesta.txt` tienen que coincidir con esas cubetas.

</details>

<details>
<summary>Qué debería ver</summary>

Las peticiones rápidas imprimen 200 con unos milisegundos de time_total y las lentas, 200 con algo más de 2 segundos (en la corrida del autor, entre 2.0021 y 2.0040). Tras 30 segundos, sum by (le) (istio_request_duration_milliseconds_bucket{reporter="source",destination_service_name="pesaje"}) ordenado con sort -g cuenta PESAJES_RAPIDOS hasta la cubeta de 1000, PESAJES_RAPIDOS más PESAJES_LENTOS desde la de 2500 hasta +Inf, y nada entre las dos. En la corrida del autor: 1000.0 8, 2500.0 14 y +Inf 14. `04-respuesta.txt` queda con HASTA_1000_MS=8, HASTA_2500_MS=14, ENTRE_1000_Y_2500_MS=6 y OBSERVACIONES=14 para esos números.

</details>

```bash
./04-step.sh
./04-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 5. Cap. 18: De la línea del registro de acceso a la traza completa (10 pts)

Objetivo: en el espacio `registro`, Jaeger 2.23.0 (OTLP por gRPC en el 4317 y la consulta en el 16686) y el Collector 0.165.0 que le reenvía las trazas, en la dirección que el proveedor `trazador` del Paso 1 espera; una Telemetry `todo-el-trafico` en `istio-system` que traza el ciento por ciento con `trazador` y escribe el registro de acceso con `registro-json`; en `trazado`, con la inyección de Istio, la aplicación `paquetes` detrás del Gateway `entrada-trazas` con el nombre `paquetes.torre.test`; y una petición desde `sondeo` con la marca de esta corrida (`marca.txt`) en la ruta. Entregable: `05-respuesta.txt` con TRAZA (el número de traza que escribió la entrada para esa petición), TRAMOS (cuántos tramos guarda Jaeger para ella) y TRAMO_RAIZ (el identificador del tramo sin padre).

El Capítulo 18 leyó una petición tres veces: en la línea de la entrada, en la del proxy de la aplicación y en la traza que las une por el número. La marca en la ruta deja elegir su línea entre todas las del registro.

<details>
<summary>Pista del verificador (check_hint)</summary>

La comprobación exige la Telemetry `todo-el-trafico` de toda la malla con `trazador` al ciento por ciento y `registro-json`; los Pods de paquetes con istio-proxy entre los contenedores de inicio; en el registro de la entrada, una línea con la marca de esta corrida, código 200 y el número de TRAZA; una línea del sidecar de paquetes con ese mismo número; y en Jaeger esa traza con un solo tramo raíz y un tramo servidor de paquetes cuyo padre es un tramo cliente de la entrada. TRAMOS y TRAMO_RAIZ tienen que coincidir con lo que Jaeger devuelve ahora.

</details>

<details>
<summary>Qué debería ver</summary>

Jaeger y colector terminan con successfully rolled out, la Telemetry `todo-el-trafico` queda creada, paquetes y `entrada-trazas` quedan listos y la petición marcada recibe 200. La línea JSON de la entrada trae bandera -, motivo via_upstream, el nombre `paquetes.torre.test`, la ruta con la marca y un número de traza de 32 cifras hexadecimales; el sidecar de paquetes escribe su propia línea con el mismo número. Jaeger devuelve tres tramos: `entrada-trazas-istio.trazado` SERVER sin padre (la raíz), `entrada-trazas-istio.trazado` CLIENT hijo de la raíz, y paquetes.trazado SERVER hijo del tramo cliente. `05-respuesta.txt` queda con TRAZA, TRAMOS=3 y TRAMO_RAIZ.

</details>

```bash
./05-step.sh
./05-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 6. Cap. 18: Una aplicación que no contesta, diagnosticada en el orden de lectura del capítulo (10 pts)

Objetivo: en `trazado`, la aplicación `consigna` (Deployment, Service y la HTTPRoute `ruta-consigna` hacia el Gateway `entrada-trazas` con el nombre `consigna.torre.test`) contesta 200 en /get a `sondeo`. Hoy no contesta: `inyectar-falla.sh` la deja rota. Ubique la falla leyendo en el orden del Capítulo 18, repárela sin borrar ni recrear ningún objeto y deje el diagnóstico escrito. Entregables: `06-diagnostico.txt`, con una sección por lectura (== 1. lo que vio el cliente, == 2. la línea del registro de acceso de la entrada, == 3. el estado de los objetos que esa línea señala) y `06-respuesta.txt` con CODIGO_DEL_CLIENTE, BANDERA y MOTIVO (los de esa línea), OBJETO_REPARADO (tipo/nombre del objeto que cambió) y VALOR_QUE_LA_FALLA_DEJO (el valor equivocado que encontró, tal como lo leyó en el objeto).

El Capítulo 18 dejó un orden de lectura: primero el código que vio el cliente, después la línea del registro de acceso con su bandera y su motivo, luego el estado de los objetos que esa línea señala. Cada lectura acota la siguiente. Lea lo que la línea dice, no lo que espera ver.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es borrar lo que se rompió y crearlo de nuevo. La comprobación lo cierra: exige que `06-diagnostico.txt` sea más nuevo que la falla y traiga las tres secciones, con el código que vio el cliente en la primera, en la segunda la línea JSON del registro para `consigna.torre.test` con su código, su bandera y su motivo, y esa línea tiene que existir en el registro de la entrada, y en la tercera el valor que la falla dejó; que el objeto que reparó sea el mismo que dejó la falla (se compara su identidad con la que guardó el guion de la falla), que todo siga llevando a la aplicación consigna y que la entrada conteste 200 ahora. Las cinco líneas de `06-respuesta.txt` tienen que coincidir con lo que la falla dejó.

</details>

<details>
<summary>Qué debería ver</summary>

`inyectar-falla.sh` imprime falla inyectada. EL SÍNTOMA: `sondeo` pide `consigna.torre.test` y recibe 503. La línea del registro de la entrada para ese nombre trae respuesta 503, bandera UH y motivo no_healthy_upstream: según el manual de formatos de Envoy, UH es que no había ningún host sano en el clúster de destino, además del código 503. La ruta está bien (Accepted True y ResolvedRefs True), así que no es una ruta hacia un destino que no existe como la del capítulo. La Service consigna existe pero no tiene extremos listos: pide `app=consigna-v2` y los Pods de consigna llevan app=consigna. La reparación es que la Service pida la etiqueta que llevan los Pods (un patch, sin recrearla): aparece un extremo listo y la entrada devuelve 200. `06-respuesta.txt` queda con CODIGO_DEL_CLIENTE=503, BANDERA=UH, MOTIVO=no_healthy_upstream, OBJETO_REPARADO=service/consigna y `VALOR_QUE_LA_FALLA_DEJO=app=consigna-v2`.

</details>

```bash
./06-step.sh
./06-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 7. Cap. 18: Una clave más en el registro de un solo proxy, solo con el objetivo (punto sin resolver) (10 pts)

El examen no le da el comando: le da una tarea escrita como objetivo. Este paso es esa situación en pequeño: no trae receta, y el setup dejó la ficha en un archivo que cambia en cada corrida, como el dato que el examen pone en el enunciado. Tampoco hay archivo de respuesta: lo que se califica es el estado del clúster.

El objetivo está escrito como comentario al final del cmd del paso. Léalo con calma, escriba en una línea cada condición que tiene que cumplirse, y arme el estado final de a una. Un cambio de configuración tarda en llegar a los proxies: cuando algo no aparezca, repita la petición mirando el tiempo antes de cambiar otra cosa.

<details>
<summary>Pista del verificador (check_hint)</summary>

Este es el punto sin resolver: la comprobación falla con el estado guiado de los Pasos 1 a 6 porque ningún proxy escribe la clave ficha, hasta que usted lo resuelva. La comprobación repite sus peticiones con espera durante varios minutos antes de fallar. Los atajos que cierra: editar la ficha (se compara con una huella que el setup guardó aparte) y escribir la clave también en otros proxies: la comprobación lee las dos entradas y a consigna, y comprueba lo que el objetivo dice que queda igual. Las peticiones de la comprobación llevan fichas nuevas en cada corrida, así que una línea vieja no basta: el proxy de paquetes tiene que escribir la ficha de la petición que llega ahora.

</details>

<details>
<summary>Qué debería ver</summary>

No se publica la secuencia de comandos de este paso: es el punto sin resolver. El estado final correcto: el proxy de los Pods de paquetes escribe, por cada petición, una línea JSON con las ocho claves (bandera, ficha, motivo, ms, nombre, respuesta, ruta y traza), y ficha trae el valor de la cabecera x-ficha; las dos entradas y el proxy de consigna siguen con las siete claves del Paso 1; la configuración que dejó el Paso 5 para toda la malla sigue como estaba; y en el registro de paquetes hay una línea con la ficha de esta corrida cuya traza guarda Jaeger con un tramo de paquetes. La comprobación manda sus propias peticiones con fichas nuevas y repite con el tiempo a la vista hasta que el cambio llega.

</details>

```bash
./07-step.sh
./07-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

## Cómo correrlo

```bash
./00-setup.sh                  # crea el clúster y deja todo listo
./01-step.sh && ./01-check.sh  # haga el paso, compruebe que quedó bien
./02-step.sh && ./02-check.sh
./03-step.sh && ./03-check.sh
./04-step.sh && ./04-check.sh
./05-step.sh && ./05-check.sh
./06-step.sh && ./06-check.sh
./07-step.sh && ./07-check.sh
./99-teardown.sh               # borra el clúster y el espacio de trabajo
```

## Si algo falla

- **Síntoma (step 1):** count by (job) (up) no trae el trabajo kube-proxy, o trae sus objetivos en 0
  **Qué hacer:** kube-proxy publica sus métricas en 127.0.0.1 si no se le cambia metricsBindAddress, y Prometheus corre en otro Pod. Mire la configuración del clúster de kind con la que creó la torre y el trabajo kube-proxy de los valores de Prometheus; si cambió el clúster, hay que crearlo de nuevo.

- **Síntoma (step 1):** `pregunta.sh` no imprime nada
  **Qué hacer:** Prometheus raspa cada 10 segundos y necesita al menos un raspado de cada objetivo. Espere medio minuto y repita; si sigue vacío, mire que el Pod de `prometheus-server` esté 2/2 en vigilancia.

- **Síntoma (step 2):** El contador dice más peticiones que el pedido
  **Qué hacer:** Se contó alguna petición de prueba. El contador vive en el proxy de la entrada: reinicie el Deployment `entrada-torre-istio` en faena, espere a que esté listo y mande el pedido una sola vez. Eso también borra lo que el Paso 4 haya contado, así que hágalo antes de ese paso.

- **Síntoma (step 2):** No aparece ninguna serie después de la ráfaga
  **Qué hacer:** Mire que cada petición lleve la cabecera Host: `bodega.torre.test` y vaya al Service `entrada-torre-istio.faena`; sin el nombre, la ruta no la toma. Espere dos raspados más antes de concluir.

- **Síntoma (step 3):** Las peticiones bloqueadas reciben 200
  **Qué hacer:** La política tarda unos segundos en llegar al agente. Espere cinco segundos después del apply y mire que su podSelector elija a los Pods de bodega y que policyTypes traiga Ingress.

- **Síntoma (step 3):** El contador cambió entre la lectura y la comprobación
  **Qué hacer:** Cada intento bloqueado suma paquetes. Si repitió intentos con la política puesta, vuelva a leer el contador y escriba el valor nuevo en `03-respuesta.txt`.

- **Síntoma (step 4):** Las lentas aparecen en la cubeta de 1000
  **Qué hacer:** Mire la ruta que pidió: /delay/2 tarda dos segundos. En una corrida de prueba del autor, /delay/1 quedó contada hasta 1000 milisegundos en la entrada, aunque curl midió algo más de un segundo; con dos segundos no hay duda de cubeta.

- **Síntoma (step 4):** Las cubetas cuentan más que el pedido
  **Qué hacer:** Alguna petición de prueba quedó contada. Reinicie el Deployment `entrada-torre-istio`, espere a que esté listo y mande el pedido del Paso 2 y el de este paso una sola vez cada uno.

- **Síntoma (step 5):** Jaeger devuelve un error o ningún tramo para el número
  **Qué hacer:** Los tramos tardan unos segundos en pasar por el Collector. Espere diez segundos y repita la consulta. Si sigue vacío, mire el registro del Pod colector en registro: el exportador tiene que alcanzar jaeger.registro en el 4317.

- **Síntoma (step 5):** El registro de la entrada no tiene líneas que empiecen con {
  **Qué hacer:** El registro JSON sale del proveedor `registro-json`, que la Telemetry `todo-el-trafico` enciende. Mire que esa Telemetry esté en istio-system y que la petición se haya hecho después de crearla.

- **Síntoma (step 5):** Jaeger perdió la traza
  **Qué hacer:** Jaeger todo en uno guarda las trazas en memoria: si su Pod se reinició, las anteriores ya no están. Mande otra petición marcada y escriba `05-respuesta.txt` con el número nuevo.

- **Síntoma (step 6):** No encuentro la línea de consigna en el registro de la entrada
  **Qué hacer:** El registro es del Pod del Gateway `entrada-trazas`, en trazado. Filtre las líneas que empiezan con { y elija con jq la del nombre `consigna.torre.test`; espere unos segundos después de la petición.

- **Síntoma (step 6):** Después de reparar sigo sin recibir 200
  **Qué hacer:** Los proxies tardan unos segundos en enterarse del cambio. Espere diez segundos, repita la petición y vuelva a leer la línea del registro: si la bandera cambió, la lectura cambió también.

- **Síntoma (step 6):** La comprobación del Paso 6 falla aunque la aplicación ya contesta 200
  **Qué hacer:** Si volvió a correr `inyectar-falla.sh`, el marcador de la falla quedó más nuevo que su diagnóstico. Vuelva a leer las tres secciones, repare de nuevo y reescriba `06-diagnostico.txt` y `06-respuesta.txt`.

- **Síntoma (step 7):** La clave ficha no aparece en el registro de paquetes
  **Qué hacer:** Mire primero el tiempo: repita la petición cada diez segundos durante un minuto antes de cambiar nada. Después lea con kubectl get lo que aplicó y compárelo, campo por campo, con el objetivo.

- **Síntoma (step 7):** Mi ficha aparece, pero la comprobación dice que no
  **Qué hacer:** La comprobación lee también las otras líneas: pida por las dos entradas y a consigna, y cuente las claves de cada línea. Compare la ficha con el contenido de `~/ckne-lab/p05/ficha-de-la-bitacora.txt`: cualquier carácter de más cambia el valor.

## Para ir más lejos

- En el Paso 4, pida histogram_quantile(0.9, ...) sobre las mismas cubetas con rate de dos minutos justo después del pedido y otra vez cinco minutos más tarde. Anote los dos valores y explique con la página de funciones de Prometheus qué los separa.
- En el Paso 3, deje la política puesta y lea los descartes con Hubble desde el agente de Cilium, como en el Capítulo 18. Compare cuántos flujos DROPPED ve con lo que cuenta cilium_drop_count_total. Esto cambia el contador que mide la comprobación del Paso 3: hágalo después de comprobar los pasos.
- En el Paso 5, deje de muestrear al 100 por ciento y mande otra petición marcada. Mire qué número de traza escribe la entrada y si Jaeger la guarda. Esto puede cambiar lo que miden las comprobaciones de los Pasos 5 y 7: hágalo después de comprobarlos y devuelva el muestreo a como estaba al terminar.

## Referencias

- Prometheus, Querying functions (latest). rate, increase and histogram_quantile, and why a rate is extrapolated, used in Steps 2 and 4. https://prometheus.io/docs/prometheus/latest/querying/functions/
- Prometheus, Querying basics (latest). Label matchers and the expressions used with `pregunta.sh` in Steps 1 to 4. https://prometheus.io/docs/prometheus/latest/querying/basics/
- Kubernetes, kube-proxy configuration (v1alpha1). metricsBindAddress and its default 127.0.0.1:10249, changed in Step 1. https://kubernetes.io/docs/reference/config-api/kube-proxy-config.v1alpha1/
- Cilium Project, Installation using kind (stable). The kind configuration with the default CNI disabled, used in Step 1. https://docs.cilium.io/en/stable/installation/kind/
- Cilium Project, Monitoring and metrics (stable). The agent's metrics, among them the drop counter read in Step 3. https://docs.cilium.io/en/stable/observability/metrics/
- Istio, Istio standard metrics (latest). istio_requests_total and istio_request_duration_milliseconds, read in Steps 2 and 4. https://istio.io/latest/docs/reference/config/metrics/
- Istio, OpenTelemetry tracing task (latest). The opentelemetry extension provider and the Telemetry resource used in Step 5. https://istio.io/latest/docs/tasks/observability/distributed-tracing/opentelemetry/
- Istio, Envoy access logs task (latest). Turning on the access log with the Telemetry API, used in Step 5. https://istio.io/latest/docs/tasks/observability/logs/access-log/
- Istio, MeshConfig reference (latest). extensionProviders and envoyFileAccessLog with JSON labels, used in Steps 1 and 5. https://istio.io/latest/docs/reference/config/istio.mesh.v1alpha1/
- Envoy, Access log format and substitution operators (latest). %RESPONSE_FLAGS%, %RESPONSE_CODE_DETAILS%, %TRACE_ID% and %REQ(...)%, read in Steps 5 and 6. https://www.envoyproxy.io/docs/envoy/latest/configuration/advanced/substitution_formatter
- Envoy, Response code details (latest). The values of the motivo key read in Steps 5 and 6. https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_conn_man/response_code_details
- Gateway API, Troubleshooting (v1.6). The Accepted and ResolvedRefs conditions of a route, read in Step 6. https://gateway-api.sigs.k8s.io/docs/concepts/troubleshooting/
- Jaeger, APIs (v2.23). OTLP over gRPC on 4317 and the /api/v3/ query on 16686, used in Steps 5 and 7. https://www.jaegertracing.io/docs/2.23/architecture/apis/
- OpenTelemetry, Collector configuration. The otlp receiver, the exporter and the traces pipeline of Step 5. https://opentelemetry.io/docs/collector/configuration/
- go-httpbin v2.26.0, endpoints. /status/:code and /delay/:n used in Steps 2 and 4. https://github.com/mccutchen/go-httpbin/blob/v2.26.0/httpbin/static/index.html.tmpl

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
