# Parte I - Laboratorio: levante el aeropuerto de práctica con tres terminales y sin pistas, tienda los pasillos de Calico, y demuestre que el reglamento de la red se cumple entre terminales

- Tiempo: 50 min
- Puntos: 50

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solamente el objetivo y el entregable, y la secuencia de comandos del paso vive en el campo cmd para que la revele después de haber intentado por su cuenta. La excepción es el Paso 5: ese solo declara el objetivo, no hay comando publicado en ningún lado del repositorio, y su comprobación depende de una ficha de vuelo distinta en cada corrida. Qué se construye: el Paso 1 monta el escritorio del examen (Capítulo 1): un clúster kind llamado ckne-lab0 con un plano de control y dos trabajadores, con el CNI por defecto desactivado (disableDefaultCNI) y con la subred de Pods y la de Services escritas de forma explícita. Esos nodos quedan sin pistas hasta el Paso 2. El Paso 2 instala Calico v3.33.0 con el manifiesto oficial de esa versión y exige que los tres nodos queden Ready y que el pool de IPs de Calico coincida con la subred de Pods que usted declaró (Capítulo 2). El Paso 3 prueba la primera regla del modelo de red: dos Pods en nodos distintos con IP de la subred de Pods, y el receptor ve como origen la IP del emisor, sin NAT en el camino (Capítulo 2). El Paso 4 prueba la regla del Service: un ClusterIP que CoreDNS resuelve por nombre y que reparte las peticiones entre dos réplicas (Capítulo 2). El Paso 5 es el examen en miniatura: un Pod y un Service con un requisito escrito solo como objetivo. Ninguna comprobación lee su historial: todas vuelven a consultar el clúster vivo en el momento de calificar, y las de los Pasos 3, 4 y 5 lanzan peticiones nuevas con marcas que usted no puede conocer de antemano.

## Prerrequisitos

- Una máquina Linux con kind, kubectl, docker y jq en el PATH, y con al menos 4 GB de RAM libres para tres nodos. El laboratorio crea su propio clúster kind llamado ckne-lab0 y lo elimina en el teardown.
- AISLAMIENTO. El clúster de este laboratorio NUNCA toca su kubeconfig de siempre: se crea con --kubeconfig ~/ckne-lab/p00/kubeconfig desde el primer comando, y todos los kubectl del laboratorio pasan --kubeconfig y --context explícitos. Si ya tiene otros clústeres de kind, este laboratorio no los ve, no los modifica y no los borra. El setup imprime kind get clusters antes de empezar para que lo compruebe.
- Acceso a internet durante todo el laboratorio: kind descarga la imagen del nodo, el Paso 2 baja el manifiesto de Calico desde raw.githubusercontent.com y las imágenes de quay.io, y los Pods de los Pasos 3 a 5 bajan una imagen de busybox fijada por digest desde docker.io.
- VERSIONES FIJADAS, verificadas el 2026-11-13 en esta misma máquina. kind v0.33.0 (mínimo v0.33.0). kubectl v1.37.0. Imagen del nodo kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5. Calico v3.33.0 con el manifiesto https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml. Imagen de los Pods busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. Un tag es mutable y un digest no. Confirme lo que le quedó instalado con kind version y kubectl version, nunca de memoria.
- Haber leído los Capítulos 1 y 2. Este laboratorio no vuelve a explicar el formato del examen ni las reglas del modelo de red; le hace operarlas contra un clúster real y le califica el estado final. Los pasos son dependientes: el 2 necesita el clúster del 1, y los 3, 4 y 5 necesitan Calico del 2.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 1: El escritorio del examen se monta antes de empezar, y el aeropuerto arranca sin pistas (10 pts)

El Capítulo 1 le explicó que el examen es de desempeño: usted trabaja contra clústeres reales, con un escritorio que ya viene armado y un tiempo contado. Aquí le toca armar el escritorio de práctica, y lo primero que decide es qué clase de aeropuerto es. Un clúster kind es un aeropuerto hecho con tres contenedores de Docker que hacen de terminales: uno de control y dos de trabajo. Por defecto kind le instala unas pistas de rodaje básicas llamadas kindnet, para que todo funcione sin que usted decida nada. En este libro no las queremos, porque la mitad del examen consiste en saber instalar y revisar el CNI, así que se desactivan con disableDefaultCNI.

Hay dos números que conviene escribir a mano en vez de heredar: la subred de Pods y la subred de Services. La primera es el rango de números de puerta que se reparte entre las terminales: el plano de control anota para cada nodo un pedazo (un /24, el podCIDR) y el CNI decide cómo usar el rango: Calico, como verá, reparte las IP de los Pods desde su propio pool. La segunda es el rango de las direcciones virtuales de los Services, que no están en ninguna interfaz de red: las resuelve kube-proxy con reglas del nodo. Escribirlas explícitas le obliga a saber cuáles son, y más adelante Calico tiene que coincidir con la primera.

Fíjese en la señal que da el clúster al terminar: los nodos están NotReady. No es una falla. El kubelet no declara listo un nodo mientras no encuentre una configuración de red en /etc/cni/net.d, y en un aeropuerto sin pistas todavía no puede despegar ningún avión.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es crear un clúster kind con el CNI por defecto y declarar que el aeropuerto está listo. La comprobación lo cierra: exige que el DaemonSet kindnet no exista y que /etc/cni/net.d de los tres nodos no tenga ningún archivo de kindnet, y exige que kubeadm-config diga exactamente podSubnet 192.168.0.0/16 y serviceSubnet 10.100.0.0/16, o sea que las subredes se escribieron de forma explícita y no se heredaron del valor por defecto de kind. También lee los podCIDR de los nodos del API vivo: tres, distintos, dentro de la subred de Pods. Si el clúster ya existe con otra subred no hay forma de cambiarla: borre el clúster con kind delete cluster --name ckne-lab0 --kubeconfig ~/ckne-lab/p00/kubeconfig y vuelva a crearlo con el archivo de configuración. El control sigue en pie: kube-proxy tiene que existir. Las líneas de 01-respuesta.txt se comparan con el clúster vivo, no con lo que usted recuerde.

</details>

<details>
<summary>Qué debería ver</summary>

El kind create termina con Set kubectl context to kind-ckne-lab0. get nodes muestra tres nodos, uno control-plane y dos sin rol, los tres en NotReady y con versión v1.37.0: NotReady es lo correcto, porque no hay CNI y el kubelet no declara listo un nodo que no tiene red de Pods. get daemonsets en kube-system muestra solo kube-proxy: no aparece kindnet, que es el CNI que kind instala si usted no lo desactiva. Cada nodo recibe su propio pedazo de la subred de Pods en la columna PODCIDR (un /24 distinto por nodo, todos dentro de 192.168.0.0/16). El grep sobre kubeadm-config devuelve las dos líneas, podSubnet: 192.168.0.0/16 y serviceSubnet: 10.100.0.0/16, y el ls de /etc/cni/net.d no imprime nada o no lista ningún archivo de kindnet. Guarde en 01-respuesta.txt las líneas PODSUBNET=, SERVICESUBNET=, NODOS= y PODCIDR_DEL_TRABAJADOR= con lo que acaba de ver.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 2: Los pasillos de Calico se tienden con el manifiesto oficial, y el pool de números de puerta tiene que coincidir con el que usted declaró (10 pts)

El Capítulo 2 puso sobre la mesa el contrato: todo Pod tiene su propia IP, y cualquier Pod puede hablar con cualquier otro sin traducción de direcciones. Pero Kubernetes no cumple ese contrato por sí solo: delega en un plugin de red, el CNI. Calico es uno de ellos. En el aeropuerto, Kubernetes es la torre que asigna a cada avión una puerta, y Calico es la empresa que de verdad pavimenta las pistas y pone la señalización entre terminales.

Se instala con un manifiesto de la propia documentación oficial de Calico para esa versión, fijada en la URL (v3.33.0). Fíjese que la URL lleva la versión dentro: si usara la rama principal sin fijar, el laboratorio cambiaría de un día a otro. Después de aplicarlo no hay que adivinar nada, hay que esperar al DaemonSet, que corre un agente por nodo, y al controlador, que mantiene el estado de IPAM.

Hay una pieza que el manifiesto deja con su valor por defecto y que usted tiene que verificar: el IPPool. Es el rango del que Calico reparte direcciones a los Pods. En el manifiesto de este laboratorio el rango por defecto es 192.168.0.0/16, y por eso en el Paso 1 se escogió esa podSubnet. Cuando en su clúster real el rango del plano de control y el pool de Calico no coinciden, los síntomas parecen de red pero el defecto está en dos números que no se parecen.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es poner los nodos en Ready con otro CNI, o con una versión de Calico distinta a la fijada. La comprobación exige que calico-node esté corriendo en los tres nodos con la imagen etiquetada v3.33.0, que calico-kube-controllers esté listo, que cada nodo tenga el archivo 10-calico.conflist en su /etc/cni/net.d, y que kindnet no exista. Lo que más falla es el amarre de las subredes: el CIDR del IPPool de Calico tiene que ser exactamente el podSubnet del Paso 1 (192.168.0.0/16), y se lee del objeto vivo, no del manifiesto que usted aplicó. Los Pods de CoreDNS tienen que estar Running con IP dentro de esa subred: si quedaron en ContainerCreating, mire con describe pod el evento del sandbox. Si calico-node se queda en 0/1 un rato, es normal: espere el rollout status.

</details>

<details>
<summary>Qué debería ver</summary>

El create imprime unos cuarenta objetos creados: CRDs, ServiceAccounts, ClusterRoles, el DaemonSet calico-node y el Deployment calico-kube-controllers. Los dos rollout status terminan con successfully rolled out, y el wait deja los tres nodos con condition met. get nodes ahora muestra los tres en Ready: Calico escribió la configuración de red en /etc/cni/net.d y el kubelet ya puede declarar listo el nodo. La imagen del DaemonSet termina en :v3.33.0. El pool de IPs se llama default-ipv4-ippool y su CIDR es 192.168.0.0/16, igual a la podSubnet del Paso 1: ese es el amarre que no se puede olvidar, porque un pool que no coincide con el rango que el plano de control reparte deja Pods con direcciones que nadie sabe enrutar. El ls de /etc/cni/net.d lista el archivo 10-calico.conflist y la carpeta calico-kubeconfig. Los dos Pods de CoreDNS ya tienen IP dentro de 192.168.0.0/16. Guarde en 02-respuesta.txt las líneas VERSION_DE_CALICO=, POOL_DE_IPS= y NODOS_LISTOS=.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 2: Dos maletas en terminales distintas se hablan sin que nadie les cambie la etiqueta de origen (10 pts)

Esta es la primera regla del contrato de red, y es la que más se da por sentada: los Pods se hablan entre sí, en cualquier nodo, usando sus IP reales, sin traducción de direcciones (NAT). Piense en dos maletas con la etiqueta del dueño pegada: cuando una maleta cruza de la terminal A a la terminal B, la etiqueta de origen llega intacta. Si alguien en el camino le cambiara la etiqueta por la de la aduana, el receptor ya no sabría de quién viene, y ninguna regla basada en el origen serviría.

Para probarlo no basta con que la petición llegue: hay que mirar con qué origen llegó. Por eso el receptor es un servidor que registra el cliente. Y por eso los dos Pods se fijan a nodos distintos con nodeName: un Pod que hablara con otro del mismo nodo no probaría nada sobre la red entre terminales, porque ese tráfico nunca la cruza.

La comprobación es dura a propósito, porque es la que más veces se salta en la práctica: no se fía de lo que usted guardó en el archivo, manda su propia petición con una marca nueva y lee quién fue visto como origen.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es poner los dos Pods en el mismo nodo, donde el tráfico nunca sale por la red entre nodos, o usar hostNetwork para que compartan la IP del nodo. La comprobación exige nodos distintos, hostNetwork falso, IP de cada Pod dentro de la subred de Pods 192.168.0.0/16, y luego no se conforma con lo que usted hizo: lanza ella misma una petición nueva con una marca aleatoria desde el emisor al receptor, busca esa marca en el log del receptor y exige que la IP de origen que ve sea la del Pod emisor y no una IP 172.18.X.X de nodo. El receptor tiene que registrar las peticiones con su IP de origen: httpd -vv de busybox lo hace, y cualquier servidor que registre la dirección del cliente sirve. Si el wget del emisor se cuelga, Calico no está enrutando entre nodos: vuelva a revisar el Paso 2.

</details>

<details>
<summary>Qué debería ver</summary>

get pods -o wide muestra emisor en ckne-lab0-worker y receptor en ckne-lab0-worker2, los dos Running, con IP dentro de 192.168.0.0/16, y las dos de bloques distintos (Calico reparte a cada nodo un bloque propio de su pool). El wget termina con un error 404 Not Found, y eso es lo esperado: el receptor es un httpd sin ninguna página, y lo que interesa no es la respuesta sino la línea que la petición dejó en el log del receptor. Esa línea tiene la forma [::ffff:192.168.X.Y]:PUERTO: url:/mi-sonda, y la IP entre corchetes es la IP del Pod emisor, la misma que imprime el último comando. No es la IP del nodo del emisor (172.18.0.X, la de la red de Docker): si lo fuera, alguien habría traducido el origen en el camino. Guarde en 03-respuesta.txt las líneas IP_DEL_EMISOR= e IP_QUE_VIO_EL_RECEPTOR=, y las dos deben ser iguales.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 2: Un número de ventanilla que no está en ninguna terminal, resuelto por nombre y repartido entre dos mostradores (10 pts)

Los Pods nacen y mueren, y sus IP con ellos. Si un cliente tuviera que memorizar la IP de un Pod, el primer reemplazo lo dejaría hablando con un puerto vacío. El Service es el número de ventanilla del aeropuerto: una dirección estable detrás de la cual atienden uno o varios mostradores, y los pasajeros no saben ni preguntan cuál. Esa dirección virtual, la ClusterIP, no está en ninguna interfaz de ningún nodo: kube-proxy escribe reglas en cada nodo que reescriben el destino hacia uno de los Pods listos.

Hay dos piezas más. La primera, el EndpointSlice: es la lista que el plano de control mantiene de a qué Pods apuntar, y solo incluye los que están listos. La segunda, CoreDNS: convierte el nombre `mostrador.terminal.svc.cluster.local` en la ClusterIP. El cliente nunca ve la IP, pide el nombre, y por eso el Pod emisor del Paso 3 se reutiliza aquí como cliente.

Que reparta no se afirma con una petición: una sola cae en un Pod y no demuestra nada. Por eso la comprobación manda cuarenta y exige ver a los dos mostradores.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es hacer el Service headless (clusterIP: None), que se resuelve a las IP de los Pods y no a una IP virtual, o apuntar a un solo Pod. La comprobación exige un ClusterIP real dentro de 10.100.0.0/16, que el EndpointSlice tenga exactamente las IP de los Pods Ready del Deployment, que el nombre del Service resuelva por CoreDNS a esa misma IP (lo pregunta ella, desde el Pod emisor), y que cuarenta peticiones nuevas por el nombre lleguen a todos los Pods y solo a ellos. También exige que kube-proxy siga listo en los tres nodos y que CoreDNS siga en pie: no se vale desmontar la pieza que hace el trabajo. Si nslookup falla con timeout, CoreDNS no responde: revise los Pods de kube-dns del Paso 2. Si el EndpointSlice sale vacío, el selector del Service no coincide con las etiquetas de los Pods.

</details>

<details>
<summary>Qué debería ver</summary>

El rollout termina con successfully rolled out. get svc muestra mostrador de tipo ClusterIP con una CLUSTER-IP dentro de 10.100.0.0/16 (la serviceSubnet del Paso 1) y puerto 80/TCP, sin EXTERNAL-IP. El EndpointSlice del Service acaba listando dos direcciones (puede mostrar solo una el primer segundo, hasta que el segundo Pod esté listo), que son las IP de los dos Pods del Deployment, en el puerto 8080. nslookup contesta con dos bloques: el Server es la IP del Service kube-dns (10.100.0.10) y la respuesta, Name `mostrador.terminal.svc.cluster.local`, trae como Address la CLUSTER-IP del Service, la misma que vio en get svc. Y los ocho wget imprimen nombres de Pods, y entre los ocho tienen que aparecer los dos nombres del Deployment: el Service reparte. Guarde en 04-respuesta.txt las líneas CLUSTER_IP=, RESUELVE_A= y MOSTRADORES_DISTINTOS=.

</details>

```bash
./04-step.sh
./04-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 5. Cap. 2: El mostrador de radar, como en el examen, solo con el objetivo (10 pts)

El examen no le da el comando: le da una tarea escrita como objetivo y un tiempo. Este paso es esa situación en pequeño. Todo lo que necesita lo tiene de los Pasos 3 y 4: cómo fijar un Pod a un nodo, cómo exponerlo con un Service, cómo comprobar la resolución por nombre desde otro nodo. Lo que no tiene es una receta que ya sepa el orden.

Hay un detalle que cambia de una corrida a otra: la ficha de vuelo, un texto aleatorio que el setup dejó en un archivo. Es el equivalente del dato que el examen le da en el enunciado y que usted tiene que llevar hasta el lugar correcto. Tampoco hay archivo de respuesta: lo que se califica es el estado del clúster.

Lea el objetivo con calma, escriba en una línea cada condición que tiene que cumplirse, y arme el estado final de a una. Si se atasca, el cmd del paso solo imprime la ficha: las pistas están en el check_hint, que dice qué atajos están cerrados pero no cómo se hace.

<details>
<summary>Pista del verificador (check_hint)</summary>

Este es el punto sin resolver: la comprobación falla con el estado guiado de los Pasos 1 a 4 porque el namespace torre ni siquiera existe, hasta que usted lo resuelva. Los atajos que cierra: un Pod en el nodo equivocado, hostNetwork, un Service que no sea ClusterIP o headless, un EndpointSlice que no apunte a un Pod real de worker2, y editar la ficha de vuelo (se compara con una huella que el setup guardó aparte). Lo decisivo es que ella misma lanza una sonda nueva en el otro nodo y pide el nombre DNS completo: si la respuesta no es exactamente la ficha de esta corrida, falla, así que no sirve copiar una ficha de otra corrida. Y no se vale desmontar Calico ni kube-proxy para que algo funcione. Para avanzar sin solución publicada: parta del objetivo, escriba el estado que necesita y compárelo con lo que hizo en los Pasos 3 y 4.

</details>

<details>
<summary>Qué debería ver</summary>

No se publica la secuencia de comandos de este paso: es el punto sin resolver. El estado final correcto: en el namespace torre existe un Pod Running y Ready, en el nodo ckne-lab0-worker2, con IP de la subred de Pods y sin hostNetwork; un Service radar de tipo ClusterIP con puerto 80 cuyo EndpointSlice lleva la IP de ese Pod; y una petición hecha desde un Pod de otro nodo a http://radar.torre.svc.cluster.local/ devuelve como cuerpo exactamente la ficha de vuelo de esta corrida. Con lo que acaba de practicar en los Pasos 3 y 4 hay todo lo necesario.

</details>

```bash
./05-step.sh
./05-check.sh
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
./99-teardown.sh               # borra el clúster y el espacio de trabajo
```

## Si algo falla

- **Síntoma (step 1):** `kind create cluster` falla con too many open files o con el kubelet que no arranca
  **Qué hacer:** Es el límite de inotify del anfitrión, que se comparte con los nodos porque un nodo kind es un contenedor. Suba fs.inotify.max_user_instances con sysctl (el setup imprime el valor actual), borre el clúster a medias con `kind delete cluster --name ckne-lab0 --kubeconfig ~/ckne-lab/p00/kubeconfig` y repita.

- **Síntoma (step 1):** Los nodos salen Ready antes de instalar Calico
  **Qué hacer:** Se instaló el CNI por defecto: falta disableDefaultCNI: true bajo networking en el archivo de configuración, o no pasó --config a `kind create cluster`. Borre el clúster y créelo otra vez.

- **Síntoma (step 2):** El create falla con una CRD demasiado grande o con una anotación demasiado larga
  **Qué hacer:** Es el límite de tamaño del aplicado del lado del cliente. Use kubectl create -f (como en el paso) o kubectl apply --server-side -f, que es lo que la documentación de Calico indica para este manifiesto. No use kubectl apply sin --server-side.

- **Síntoma (step 2):** Los nodos siguen NotReady y calico-node está en Init o en CrashLoopBackOff
  **Qué hacer:** Mire kubectl -n kube-system describe pod del calico-node que falla y sus logs con -c upgrade-ipam o -c install-cni si está en Init. Lo más común en kind es que no se pueda bajar la imagen de quay.io: pruebe docker pull quay.io/calico/node:v3.33.0 en el anfitrión para confirmar la red.

- **Síntoma (step 3):** Los Pods se quedan en ContainerCreating
  **Qué hacer:** Mire kubectl -n terminal describe pod emisor. Si el evento habla de un sandbox o de un plugin de red, Calico no terminó de arrancar en ese nodo: confirme el Paso 2. Si habla de la imagen, el nodo no pudo bajar busybox de docker.io.

- **Síntoma (step 3):** El log del receptor está vacío aunque el wget salió
  **Qué hacer:** Faltó el -vv en el httpd del receptor: sin esa bandera busybox no registra las peticiones. Recree el Pod receptor con el comando del paso. Si el wget se cuelga y no responde, no es el log: revise que el receptor escuche en el puerto 8080.

- **Síntoma (step 4):** El wget por el nombre del Service falla con bad address
  **Qué hacer:** La resolución falló. Pruebe nslookup desde emisor y mire kubectl -n kube-system get pods -l k8s-app=kube-dns. Recuerde el nombre completo: desde el mismo namespace basta mostrador, desde otro hace falta mostrador.terminal.

- **Síntoma (step 4):** Todas las respuestas vienen del mismo Pod
  **Qué hacer:** O el Deployment quedó con una sola réplica lista, o la conexión se reutiliza. Revise get endpointslices: tiene que listar dos direcciones. Cada wget abre una conexión nueva, así que con dos réplicas listas el reparto aparece enseguida.

- **Síntoma (step 5):** Mi Service responde pero la comprobación dice que no
  **Qué hacer:** Compare lo que responde con el contenido exacto de ~/ckne-lab/p00/ficha-de-vuelo.txt: un salto de línea al final no importa, pero cualquier otro carácter sí. Pida el nombre completo `radar.torre.svc.cluster.local` desde un Pod del otro nodo y mire el EndpointSlice: tiene que apuntar a un Pod Running de ckne-lab0-worker2.

## Para ir más lejos

- Rompa el Paso 2 a propósito para ver el síntoma completo. Borre el IPPool de Calico y cree un Pod nuevo en un nodo: mire en qué estado queda y qué evento dice, y qué le pasa a la comunicación entre un Pod nuevo y uno viejo. Después restablezca el pool con el mismo CIDR y quédese con la conclusión: la subred que reparte el plano de control y el pool del CNI son dos números que alguien tiene que mantener iguales.
- Repita el Paso 3 con un tercer Pod en el nodo del control plane y compare las tres IP de origen. Compare también la columna PODCIDR de get nodes con las IP reales de los Pods: Calico reparte bloques propios de su IPPool y no usa el /24 que el plano de control le asignó a cada nodo. Después use kubectl exec en un nodo (docker exec ckne-lab0-worker) y mire la tabla de rutas con ip route: busque la ruta hacia el /24 del otro trabajador y averigüe por qué interfaz sale. Es el adelanto del Capítulo 3.

## Referencias

- Calico Project, Install Calico on a kind cluster. The basis of Steps 1 and 2: the kind configuration with disableDefaultCNI and podSubnet, and the manifest URLs pinned to v3.33.0, including the advice to use kubectl create or replace, or apply --server-side, for the large CRD bundle. https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind
- kind Project, Configuration. Documents the networking section of the kind config: disableDefaultCNI, podSubnet and serviceSubnet, and the --config, --image and --kubeconfig flags used in Step 1. https://kind.sigs.k8s.io/docs/user/configuration/
- Kubernetes Project, Cluster Networking. The statement of the network model that Step 3 tests: every Pod gets its own IP address and Pods can communicate with all other Pods without NAT. https://kubernetes.io/docs/concepts/cluster-administration/networking/
- Kubernetes Project, Service. The basis of Step 4: ClusterIP, the virtual IP that kube-proxy implements, selectors and EndpointSlices, and headless Services as the contrast case. https://kubernetes.io/docs/concepts/services-networking/service/
- Kubernetes Project, DNS for Services and Pods. How a Service gets the name service.namespace.svc.cluster.local and how it resolves to the ClusterIP, the contract used by the checks of Steps 4 and 5. https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- Kubernetes Project, Assigning Pods to Nodes. nodeName as the way of pinning a Pod to a node, used in Steps 3 and 5 to force cross-node traffic. https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
