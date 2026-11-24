# Parte II - Laboratorio: una terminal con la pista rota, el inspector de paquetes que encuentra la falla, y una segunda puerta de abordaje con Multus

- Tiempo: 60 min
- Puntos: 60

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solamente el objetivo y el entregable, y la secuencia de comandos del paso vive en el campo cmd para que la revele después de haber intentado por su cuenta. La excepción es el Paso 6: ese solo declara el objetivo, no hay comando publicado en ningún lado del repositorio, y su comprobación depende de una ficha y de una subred distintas en cada corrida. Qué se construye: el Paso 1 monta el escritorio (Capítulo 3): un clúster kind llamado ckne-lab1 con un plano de control y dos trabajadores, sin CNI por defecto, con Calico v3.33.0, y con tcpdump instalado dentro de cada nodo (Capítulo 5), porque la imagen de nodo de kind no lo trae. El Paso 2 pone dos Pods vecinos en terminales distintas, comprueba que se hablan y entonces corre inyectar-falla.sh, un guion que rompe la red de un nodo a ciegas: su contenido va codificado a propósito, como una venda de cortesía y no como un secreto real, y la solución está al final en el archivo de respuestas. El Paso 3 es el diagnóstico (Capítulo 5): con docker exec dentro del nodo y tcpdump hay que ver por dónde llegan los paquetes y por dónde dejan de aparecer. El Paso 4 repara la causa y no el síntoma (Capítulo 3): la comprobación exige que el túnel de Calico siga siendo el mismo, así que cambiar el modo del pool para esquivar la falla no cuenta. El Paso 5 añade una segunda interfaz con Multus v4.3.2 (Capítulo 4): una NetworkAttachmentDefinition con el plugin bridge e IPAM host-local, y tráfico demostrado por net1 entre dos Pods. El Paso 6 es el examen en miniatura: otra red adicional con una subred y una ficha que cambian en cada corrida, sin comando publicado.

## Prerrequisitos

- Una máquina Linux con kind, kubectl, docker, jq, curl y tar en el PATH, y con al menos 4 GB de RAM libres para tres nodos. El laboratorio crea su propio clúster kind llamado ckne-lab1 y lo elimina en el teardown.
- AISLAMIENTO. El clúster de este laboratorio NUNCA toca su kubeconfig de siempre: se crea con --kubeconfig ~/ckne-lab/p01/kubeconfig desde el primer comando, y todos los kubectl del laboratorio pasan --kubeconfig y --context explícitos. Si ya tiene otros clústeres de kind, este laboratorio no los ve, no los modifica y no los borra. El setup imprime kind get clusters antes de empezar para que lo compruebe.
- Acceso a internet durante todo el laboratorio: kind descarga la imagen del nodo; el Paso 1 baja el manifiesto de Calico desde raw.githubusercontent.com, las imágenes de quay.io y el paquete tcpdump de los repositorios de Debian dentro de cada nodo; el Paso 5 baja los plugins CNI de referencia desde github.com y Multus desde raw.githubusercontent.com y ghcr.io; los Pods bajan una imagen de busybox fijada por digest desde docker.io.
- VERSIONES FIJADAS, verificadas el 2026-11-13 en esta misma máquina. kind v0.33.0 (mínimo v0.33.0). kubectl v1.37.0. Imagen del nodo kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5. Calico v3.33.0 con el manifiesto https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml (modo IPIP Always por defecto en el pool). Multus v4.3.2 con el manifiesto https://raw.githubusercontent.com/k8snetworkplumbingwg/multus-cni/v4.3.2/deployments/multus-daemonset-thick.yml y la imagen ghcr.io/k8snetworkplumbingwg/multus-cni:v4.3.2-thick (el manifiesto de esa etiqueta trae snapshot-thick, una etiqueta móvil, y el Paso 5 la cambia por la fija). Plugins CNI de referencia v1.10.0 de github.com/containernetworking/plugins: la imagen de nodo de kind trae host-local pero NO bridge, así que el Paso 5 instala el binario bridge verificando su huella SHA-256. Imagen de los Pods busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. tcpdump viene del repositorio de Debian del nodo y no se fija por versión (el Paso 1 imprime la que quedó). Un tag es mutable y un digest no. Confirme lo que le quedó instalado con kind version y kubectl version, nunca de memoria.
- Haber leído los Capítulos 3, 4 y 5. Este laboratorio no vuelve a explicar cómo el kubelet lee /etc/cni/net.d, ni qué es una red secundaria, ni cómo se lee una captura; le hace operarlos contra un clúster real y le califica el estado final. Los pasos son dependientes: el 2 necesita el clúster del 1, el 3 y el 4 necesitan los Pods y la falla del 2, y el 5 y el 6 necesitan el clúster del 1 (y se hacen con la red ya reparada).

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 3: El escritorio con las pistas de Calico, y el inspector de paquetes instalado en cada terminal (10 pts)

Este es el escritorio de práctica del examen de red: un clúster desechable, la red de Pods ya tendida y las herramientas de diagnóstico dentro de cada terminal. Lo único que usted construye de cero aquí es la parte que el examen le da armada y que en la vida real alguien tuvo que dejar lista. Fíjese en un detalle del Capítulo 5 que este paso resuelve por adelantado: un nodo de kind es un contenedor mínimo y no trae tcpdump. En un clúster real la herramienta suele estar en el nodo o se usa un Pod efímero con ella. Aquí se instala con el apt del propio nodo, y cada vez que el nodo se recrea hay que repetirlo.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es dejar el CNI por defecto de kind o instalar otra versión de Calico. La comprobación lo cierra: exige que el DaemonSet kindnet no exista, que la imagen de calico-node tenga la etiqueta v3.33.0 con sus tres Pods listos, que el pool sea 192.168.0.0/16 en modo Always y que tcpdump responda dentro de los tres nodos (el inspector tiene que estar en cada terminal antes de la falla). Las líneas de 01-respuesta.txt se comparan con el clúster vivo, no con lo que usted recuerde.

</details>

<details>
<summary>Qué debería ver</summary>

El kind create termina con Set kubectl context to kind-ckne-lab1. El create de Calico crea los objetos del manifiesto y los dos rollout status terminan con successfully rolled out. get nodes muestra tres nodos en Ready con versión v1.37.0. En cada nodo, el bucle imprime la versión de tcpdump que quedó instalada. El último comando imprime el CIDR del pool, 192.168.0.0/16, y su modo IPIP, Always: ese Always es el dato que importa en el resto del laboratorio, porque con él los paquetes entre Pods de nodos distintos viajan encapsulados en IP dentro de IP. Guarde en 01-respuesta.txt las líneas VERSION_DE_CALICO=, NODOS_LISTOS=, POOL_DE_IPS= y MODO_IPIP= con lo que acaba de ver.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 3: Dos vecinos en terminales distintas, y la falla que se inyecta a ciegas (10 pts)

Hasta aquí todo funcionaba, y eso es lo que hace útil una falla: usted tiene una referencia de cómo se ve la red sana. Los dos vecinos están a propósito en nodos distintos, porque dos Pods del mismo nodo se hablan por el puente local y nunca tocarían el camino roto. El guion de inyección no es un secreto: se puede leer, y está codificado solo para que usted no se encuentre la falla servida en el texto y ponga el diagnóstico en piloto automático. Trátelo como la venda de cortesía que es. Lo que sí es real es el síntoma, y es el que encuentra todo operador: algo que ayer funcionaba hoy se queda esperando y termina en un timeout, sin un mensaje de error que diga por qué.

<details>
<summary>Pista del verificador (check_hint)</summary>

Esta comprobación vale en dos momentos: con la falla puesta y después de repararla. Exige los dos Pods en sus nodos, sin hostNetwork, y que la marca de que la falla se aplicó exista. Luego mide el estado real y lo cruza con la causa: si la regla que descarta paquetes IP-en-IP está presente en el nodo, vecino-a NO puede alcanzar a vecino-b; si la regla ya no está, SÍ puede. Una mezcla de las dos cosas (falla puesta pero alcanzable, o reparada pero inalcanzable) falla, de modo que no sirve fingir el síntoma ni ocultarlo. Las líneas de 02-respuesta.txt se comparan con la IP viva de vecino-b.

</details>

<details>
<summary>Qué debería ver</summary>

get pods muestra vecino-a en ckne-lab1-worker y vecino-b en ckne-lab1-worker2, ambos Running, con IP dentro de 192.168.0.0/16. ANTES DE LA FALLA, el wget devuelve vecino-b-ok: los dos vecinos se hablan a través del túnel de Calico. Después corre inyectar-falla.sh, que imprime falla inyectada. DESPUES DE LA FALLA, el wget no devuelve nada y termina con download timed out (el || true evita que el error corte el guion). Guarde en 02-respuesta.txt las líneas IP_DE_VECINO_B= (la IP real), ANTES=responde y DESPUES=agota-tiempo.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 5: El inspector de paquetes dentro de la terminal, y la captura que localiza la falla (10 pts)

Aquí empieza la lección del Capítulo 5: un timeout no dice dónde se perdió el paquete, y el inspector sí. La técnica es la de un buscador de equipajes: no se mira el destino final ni el origen, se mira el punto medio donde el paquete tiene que aparecer, y se avanza hacia donde deja de verse. Hay tres puntos que importan en un nodo con túneles IP-en-IP: la tarjeta de red por donde llega el paquete encapsulado (eth0), la interfaz donde se abre el sobre (tunl0) y la interfaz virtual del Pod (la de nombre cali...). Que el paquete aparezca en la primera y no en la segunda acota la falla a un tramo corto, y el tramo corto se llena de reglas: iptables.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es adivinar la causa sin mirar el cable. La comprobación exige evidencia de esta corrida, no una respuesta de memoria: el archivo de eth0 tiene que traer al menos dos paquetes encapsulados que van de la IP real del nodo de vecino-a a la IP real del nodo de vecino-b, y dentro la IP viva de vecino-a hacia la IP viva de vecino-b en el puerto 8080; el archivo de tunl0 tiene que ser una captura real de esa interfaz que terminó en 0 packets captured. Las capturas de otra corrida o escritas a mano con otras IP no cuadran con el clúster vivo. Las líneas de 03-respuesta.txt resumen lo que la evidencia dice.

</details>

<details>
<summary>Qué debería ver</summary>

Los dos tcpdump corren dentro de ckne-lab1-worker2 mientras vecino-a intenta de nuevo el wget, que se agota. La captura de eth0 (filtrada con ip proto 4, o sea IP-en-IP) muestra varios paquetes del nodo ckne-lab1-worker hacia el nodo ckne-lab1-worker2 que llevan dentro un paquete de la IP de vecino-a hacia la IP de vecino-b en el puerto 8080, con la bandera de inicio de conexión (SYN), el mismo intento repetido cada segundo porque nadie lo contesta: los paquetes SÍ llegan al nodo. La captura de tunl0, la interfaz donde Calico desencapsula, termina con 0 packets captured: ahí NO aparece nada. Entre eth0 y tunl0 algo descarta los paquetes. Los dos últimos comandos listan las interfaces y las reglas de iptables del nodo para que usted busque el culpable. Guarde en 03-respuesta.txt las líneas NODO_CON_FALLA=, PROTOCOLO_IP= (el número de protocolo IP que usa el túnel), LLEGA_A_ETH0= y LLEGA_A_TUNL0=.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 3 y 5: Reparar la causa y no el síntoma, y demostrar que la respuesta vuelve por el túnel (10 pts)

Una reparación tiene dos mitades: quitar la causa y demostrar que quitó el síntoma. La mitad fácil de olvidar es la segunda, y la captura la hace visible: antes se veía la petición entrar y nada salir; ahora se ve el viaje completo, ida y vuelta. También hay una razón de oficio para dejar el pool de Calico como estaba. Si la red de Pods se sostiene en un túnel y un nodo no lo deja pasar, lo correcto es devolverle el paso al túnel; apagar el túnel para todos porque un nodo falla es tapar una gotera con un cambio de arquitectura, y más tarde alguien paga la factura sin saber de dónde viene.

<details>
<summary>Pista del verificador (check_hint)</summary>

Los atajos que cierra: cambiar el pool de Calico a otro modo de encapsulación (o a ninguno) para que el tráfico esquive el túnel, que deja la falla en el nodo y cambia la red de todos; insertar una regla ACCEPT por encima de la que descarta y dejar la causa viva (la comprobación recorre iptables-save de los tres nodos y no tolera ninguna regla de descarte del protocolo 4 fuera de las cadenas de Calico); y declarar la reparación sin demostrarla (lanza una sonda nueva en otro nodo y pide a vecino-b, y exige que la captura guardada muestre la respuesta de vecino-b volviendo a vecino-a por tunl0). El control sigue en pie: el pool debe ser el mismo 192.168.0.0/16 en Always y los tres calico-node deben estar listos.

</details>

<details>
<summary>Qué debería ver</summary>

El primer comando lista las reglas de la cadena PREROUTING de la tabla raw del nodo: aparecen la regla de Calico y una regla extra que descarta el protocolo 4. El segundo la elimina y el tercero muestra que ya no está. El wget de vecino-a ahora devuelve vecino-b-ok. La captura de tunl0 (esta vez con tráfico) muestra la petición que entra por el túnel y, lo importante, la respuesta que sale de la IP de vecino-b y vuelve hacia la IP de vecino-a. El último comando confirma que el modo IPIP del pool sigue siendo Always: se reparó la causa, no se esquivó. Guarde en 04-respuesta.txt las líneas TABLA_DE_LA_REGLA=, CADENA_DE_LA_REGLA= y MODO_IPIP_INTACTO=.

</details>

```bash
./04-step.sh
./04-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 5. Cap. 4: La segunda puerta de abordaje con Multus, el plugin bridge y la IPAM host-local (10 pts)

El Capítulo 4 habla de una casa con dos puertas: una es la de siempre (eth0, la red de Pods que sostiene Calico) y la otra es una red adicional que usted define. Multus no reemplaza a Calico: se pone de primero en la lista alfabética de /etc/cni/net.d, llama a Calico para eth0 y, si el Pod lo pide con una anotación, llama a otros plugins para net1, net2 y siguientes. Dos hechos de este paso merecen quedarse. El primero: el plugin bridge no venía en el nodo, y aprender a comprobar qué binarios existen en /opt/cni/bin antes de escribir una definición es una habilidad de examen, porque la definición se acepta por el API aunque nadie pueda ejecutarla. El segundo: un puente es local a cada nodo y host-local reparte direcciones por nodo sin hablar con los demás, así que dos Pods hablan por net1 solo si están en el mismo nodo. Por eso rx y tx comparten nodo, y la sonda de la comprobación también.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es declarar la segunda interfaz sin probarla, o hacer tráfico por la interfaz equivocada. La comprobación lanza una sonda nueva con la anotación de la red adicional en el mismo nodo, le pide una ruta con una marca única a la net1 de rx, y lee el registro de rx: el origen tiene que ser la net1 de la sonda, dentro de 10.20.0.0/24; si el tráfico fue por eth0 el origen sería una IP de 192.168.0.0/16 y falla. También exige el plugin bridge ejecutable en los tres nodos, la imagen exacta v4.3.2-thick con sus tres Pods listos, la definición con plugin bridge e IPAM host-local (y ni rastro de macvlan), el puente br-pista existente en el nodo y que eth0 de rx siga siendo la red de Calico. Las líneas de 05-respuesta.txt se comparan con las IP vivas.

</details>

<details>
<summary>Qué debería ver</summary>

El primer comando lista /opt/cni/bin del nodo: aparece host-local (viene en la imagen de kind) y NO aparece bridge, que es el hallazgo de este paso. La descarga se verifica con sha256sum -c y dice OK; tras copiar el binario, ls -l muestra bridge y host-local ejecutables en los tres nodos. El grep del manifiesto muestra las dos imágenes con la etiqueta fija v4.3.2-thick. rollout status de kube-multus-ds termina con successfully rolled out. En /etc/cni/net.d del nodo aparece 00-multus.conf junto a 10-calico.conflist, y el contenido de 00-multus.conf apunta a 10-calico.conflist como red principal (clusterNetwork): Multus se pone por delante de Calico en el orden alfabético y le pasa la tarea de eth0. Los Pods rx y tx quedan Running en el mismo nodo; `ip -o -4 addr show` en tx muestra eth0 con IP de 192.168.0.0/16 y net1 con IP de 10.20.0.0/24; el wget de tx hacia la net1 de rx devuelve rx-net1-ok y el registro de rx muestra como origen la net1 de tx (10.20.0.x), no su eth0. Guarde en 05-respuesta.txt las líneas IP_NET1_DE_RX=, IP_NET1_DE_TX= e INTERFAZ_SECUNDARIA=.

</details>

```bash
./05-step.sh
./05-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 6. Cap. 4: El muelle de carga, solo con el objetivo (punto sin resolver) (10 pts)

El examen no le da el comando: le da una tarea escrita como objetivo y un tiempo. Este paso es esa situación en pequeño. Todo lo que necesita lo tiene del Paso 5: cómo se escribe una definición de red adicional, cómo se anota un Pod para usarla, cómo se lee la IP de net1 y por qué los dos extremos tienen que estar en el mismo nodo. Lo que no tiene es una receta que ya sepa el orden, ni la subred ni la ficha: ambas las dejó el setup en archivos que cambian en cada corrida, como el dato que el examen pone en el enunciado y que usted tiene que llevar hasta el lugar correcto. Tampoco hay archivo de respuesta: lo que se califica es el estado del clúster.

Lea el objetivo con calma, escriba en una línea cada condición que tiene que cumplirse, y arme el estado final de a una. Si se atasca, el cmd del paso solo imprime los dos datos de la corrida: las pistas están en el check_hint, que dice qué atajos están cerrados pero no cómo se hace.

<details>
<summary>Pista del verificador (check_hint)</summary>

Este es el punto sin resolver: la comprobación falla con el estado guiado de los Pasos 1 a 5 porque el namespace muelle ni siquiera existe, hasta que usted lo resuelva. Los atajos que cierra: una definición con otra subred o con macvlan, un faro en otro nodo o con hostNetwork, servir la ficha por eth0 y no por net1, y editar la ficha o la subred (se comparan con una huella que el setup guardó aparte). Lo decisivo es que ella misma lanza una sonda nueva con la anotación carga en el nodo del faro y pide la IP net1 del faro: si la respuesta no es exactamente la ficha de esta corrida, o la sonda no obtiene una net1 dentro de la subred de esta corrida, falla, así que no sirve copiar la ficha de otra corrida. Y no se vale desmontar Multus ni Calico para que algo funcione. Para avanzar sin solución publicada: parta del objetivo, escriba el estado que necesita y compárelo con lo que hizo en el Paso 5.

</details>

<details>
<summary>Qué debería ver</summary>

No se publica la secuencia de comandos de este paso: es el punto sin resolver. El estado final correcto: en el namespace muelle existe una NetworkAttachmentDefinition llamada carga con plugin bridge e IPAM host-local, con la subred exacta de subred-del-muelle.txt; un Pod faro Running en ckne-lab1-worker, sin hostNetwork, con eth0 de la red de Calico y una net1 con IP dentro de esa subred; y una petición hecha desde una sonda nueva en el mismo nodo, anotada con la red carga, a http://<IP de la net1 del faro>:8080/ devuelve como cuerpo exactamente la ficha de esta corrida. Con lo que acaba de practicar en el Paso 5 hay todo lo necesario.

</details>

```bash
./06-step.sh
./06-check.sh
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
./99-teardown.sh               # borra el clúster y el espacio de trabajo
```

## Si algo falla

- **Síntoma (step 1):** `kind create cluster` falla con too many open files o con el kubelet que no arranca
  **Qué hacer:** Es el límite de inotify del anfitrión, que se comparte con los nodos porque un nodo kind es un contenedor. Suba fs.inotify.max_user_instances con sysctl (el setup imprime el valor actual), borre el clúster a medias con `kind delete cluster --name ckne-lab1 --kubeconfig ~/ckne-lab/p01/kubeconfig` y repita.

- **Síntoma (step 1):** El bucle imprime una línea vacía en lugar de la versión de tcpdump
  **Qué hacer:** apt-get no pudo bajar el paquete: el nodo no tiene salida a internet o el DNS del anfitrión falla dentro de Docker. Entre al nodo con `docker exec -it ckne-lab1-worker bash`, corra `apt-get update` a la vista y lea el error. Si la red del anfitrión filtra los repositorios de Debian, el laboratorio no puede continuar: diga cuál es el bloqueo en lugar de saltarse el Paso 3.

- **Síntoma (step 2):** El wget de ANTES DE LA FALLA ya se agota
  **Qué hacer:** La red no estaba sana antes de inyectar nada. Revise que los tres calico-node estén listos (`kubectl -n kube-system get pods -l k8s-app=calico-node`) y que vecino-a y vecino-b estén en nodos distintos con `get pods -o wide`. No corra inyectar-falla.sh hasta que el wget de ANTES responda.

- **Síntoma (step 2):** inyectar-falla.sh dice que no encuentra el contenedor
  **Qué hacer:** El clúster del Paso 1 no existe o se llama distinto. Compruebe con `docker ps --format '{{.Names}}'` que ckne-lab1-worker2 está corriendo; si no, repita el Paso 1.

- **Síntoma (step 3):** La captura de eth0 sale vacía
  **Qué hacer:** O tcpdump no alcanzó a arrancar antes del wget (suba el sleep) o capturó en la interfaz equivocada: el tráfico entre nodos de kind entra por eth0 del contenedor del nodo, no por una del anfitrión. Verifique con `docker exec ckne-lab1-worker2 ip -br link` y pida `-i eth0`. Si ya reparó la falla, el tráfico llega y se ve igual en eth0, pero no habrá timeout.

- **Síntoma (step 3):** La captura de tunl0 no termina con 0 packets captured
  **Qué hacer:** Entonces tunl0 sí vio paquetes: o la falla no está puesta (corrija el orden: Paso 2 antes del 3) o capturó con otro filtro. El texto exacto que se espera es la línea de resumen que tcpdump imprime al terminar por el timeout, con el número 0 al principio.

- **Síntoma (step 4):** El comando de eliminar la regla dice que no existe (Bad rule o does a matching rule exist)
  **Qué hacer:** La regla no está escrita igual a como se inyectó, o está en otra tabla o cadena. Mire la lista del primer comando y copie la regla tal como la imprime iptables -S, cambiando -A por -D. La comprobación acepta cualquier forma de dejarla fuera, siempre que no quede en ningún nodo.

- **Síntoma (step 4):** La reparación funciona un momento y vuelve a fallar
  **Qué hacer:** Quedó otra regla de descarte (la inyección pudo repetirse si corrió inyectar-falla.sh otra vez). Lea de nuevo `iptables-save | grep -- '-p 4'` en los tres nodos: las reglas de Calico viven en cadenas llamadas cali-... y son legítimas; la que sobra cuelga directamente de PREROUTING, INPUT, FORWARD, OUTPUT o POSTROUTING.

- **Síntoma (step 5):** Los Pods rx y tx se quedan en ContainerCreating con un evento que menciona failed to find plugin bridge
  **Qué hacer:** El binario bridge no está en /opt/cni/bin del nodo donde corre el Pod. Compruebe con `docker exec ckne-lab1-worker ls /opt/cni/bin` y repita la copia con docker cp en el nodo que falte. La NetworkAttachmentDefinition se aceptó porque el API no sabe qué plugins hay en cada nodo: el error aparece solo al crear el Pod.

- **Síntoma (step 5):** Los Pods nuevos de toda la red, incluso sin anotación, se quedan sin crear
  **Qué hacer:** Multus quedó mal configurado y ahora es el primer plugin de todos los Pods. Mire `kubectl -n kube-system logs ds/kube-multus-ds` y que 00-multus.conf apunte a 10-calico.conflist. Si instaló otra variante (thin) por error, borre con el mismo manifiesto y aplique el thick de este paso.

- **Síntoma (step 6):** Mi faro responde por net1 pero la comprobación dice que no
  **Qué hacer:** Compare lo que responde con el contenido exacto de ~/ckne-lab/p01/ficha-del-muelle.txt: un salto de línea al final no importa, pero cualquier otro carácter sí. Mire que la subred de la definición carga sea exactamente la de subred-del-muelle.txt, que el faro esté en ckne-lab1-worker y que en su anotación network-status aparezca la interfaz net1.

## Para ir más lejos

- Pruebe a mano la regla del puente: ponga rx en ckne-lab1-worker y tx en ckne-lab1-worker2 con la misma definición puente-pista y pida la net1 de rx desde tx. Anote qué pasa y por qué (cada nodo tiene su propio br-pista y su propio host-local con el mismo rango). Después mire `docker exec ckne-lab1-worker ip -d link show br-pista` y la tabla de vecinos con `ip neigh` para ver las MAC de la red adicional. Es el adelanto de por qué una red adicional entre nodos necesita otra clase de plugin, que es el tema de los capítulos siguientes.
- Repita el Paso 3 contra la otra dirección: capture en ckne-lab1-worker mientras vecino-b le pide algo a vecino-a con la falla puesta. Compare cuál sentido falla y cuál no, y explique por qué la falla de entrada en un nodo rompe las peticiones que llegan a él y deja pasar las que salen de él (las respuestas de las conexiones que él abrió sí vuelven, porque no son paquetes nuevos). Para volver a poner la falla, ejecute inyectar-falla.sh de nuevo.

## Referencias

- Kubernetes Project, Cluster Networking. The statement of the network model that frames the whole lab: every Pod gets its own IP address and Pods can communicate with all other Pods without NAT. https://kubernetes.io/docs/concepts/cluster-administration/networking/
- Calico Project, Install Calico on a kind cluster. The basis of Step 1: the kind configuration with disableDefaultCNI and podSubnet, and the manifest URL pinned to v3.33.0. https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind
- Calico Project, Configure overlay networking (IP-in-IP). The explanation of why the default pool uses IP-in-IP in Always mode and what protocol 4 traffic between nodes is, the basis of Steps 3 and 4. https://docs.tigera.io/calico/latest/networking/configuring/vxlan-ipip
- tcpdump and libpcap project, tcpdump man page. The interface (-i), numeric output (-nn) and primitive filters such as ip proto used in Steps 3 and 4. https://www.tcpdump.org/manpages/tcpdump.1.html
- Multus CNI project, Quickstart Guide. The thick-plugin installation manifest used in Step 5, what the daemonset places in /opt/cni/bin and /etc/cni/net.d, and the k8s.v1.cni.cncf.io/networks annotation. https://k8snetworkplumbingwg.github.io/multus-cni/docs/quickstart.html
- Multus CNI project, release v4.3.2 and the manifest at that tag (deployments/multus-daemonset-thick.yml). The source of the exact manifest Step 5 applies, with its image swapped from snapshot-thick to v4.3.2-thick. https://github.com/k8snetworkplumbingwg/multus-cni/releases/tag/v4.3.2
- containernetworking project, CNI reference plugins v1.10.0 and the bridge plugin documentation. The source of the bridge binary Step 5 installs (the archive's SHA-256 is verified) and of the bridge and host-local configuration fields used in the NetworkAttachmentDefinition. https://github.com/containernetworking/plugins/releases/tag/v1.10.0 and https://www.cni.dev/plugins/current/main/bridge/
- kind Project, Configuration. Documents the networking section of the kind config: disableDefaultCNI, podSubnet and serviceSubnet, and the --config, --image and --kubeconfig flags used in Step 1. https://kind.sigs.k8s.io/docs/user/configuration/
- Kubernetes Project, Assigning Pods to Nodes. nodeName as the way of pinning a Pod to a node, used in Steps 2, 5 and 6 to force or avoid cross-node traffic. https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
