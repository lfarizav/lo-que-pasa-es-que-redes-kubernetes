# Parte IV - Laboratorio: un grupo de modelos con su elector, un turno que sale con dirección fija, una ruta anunciada por BGP y dos clústeres que comparten una Service

- Tiempo: 60 min
- Puntos: 70

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solamente el objetivo y el entregable, y la secuencia de comandos del paso vive en el campo cmd para que la revele después de haber intentado por su cuenta. La excepción es el Paso 7: ese solo declara el objetivo, no hay comando publicado en ningún lado del repositorio, y su comprobación depende de una ficha distinta en cada corrida. Qué se construye: el Paso 1 monta el clúster ckne-lab3 (un plano de control y dos trabajadores, Cilium 1.20.5 sin kube-proxy) con Istio 1.32.0 y la Inference Extension v1.0.1, tres servidores de modelo simulados (uno de ellos saturado a propósito), el grupo `redaccion` con su elector y la entrada `portico` con dos rutas, y compara el reparto de la ruta del grupo con el de una Service corriente (Capítulo 10). El Paso 2 corre inyectar-falla.sh, un guion que rompe a ciegas una pieza del camino de las peticiones al modelo: su contenido va codificado a propósito, como una venda de cortesía y no como un secreto real, y la solución está al final en el archivo de respuestas; hay que ubicar la avería leyendo en el orden del Capítulo 10 (el puntaje del elector, los extremos que recibe el Envoy de la entrada y, al final, los servidores de modelo) y repararla sin quitar del medio al servidor saturado (Capítulo 10). El Paso 3 hace que los Pods de un turno salgan hacia un servidor de fuera del clúster con una dirección de origen fija, y lo comprueba en el registro del destino (Capítulo 11). El Paso 4 instala MetalLB 0.16.2, lo hace hablar BGP con un enrutador FRR vecino y comprueba la ruta de una Service LoadBalancer en la tabla de ese vecino (Capítulo 11). El Paso 5 crea los clústeres ckne-lab3-uno y ckne-lab3-dos y los une con Cilium Cluster Mesh y el API de MCS (Capítulo 12). El Paso 6 exporta la misma Service desde los dos, mide el reparto entre clústeres y apaga un rato el clustermesh-apiserver de uno de ellos para leer a la vez lo que dicen el agente de Cilium y KVStoreMesh (Capítulo 12). El Paso 7 es el examen en miniatura: una Service que solo un clúster aporta y que el otro debe alcanzar por su nombre del conjunto, sin comando publicado.

## Prerrequisitos

- Una máquina Linux con kind, kubectl, docker, helm, jq, curl, tar, sha256sum, base64 y od en el PATH, y con al menos 12 GB de RAM libres: el laboratorio levanta siete nodos de kind en tres clústeres (ckne-lab3, ckne-lab3-uno y ckne-lab3-dos) y dos contenedores en la red kind (`ckne-lab3-buzon` y ckne-lab3-frontera), y los elimina todos en el teardown.
- AISLAMIENTO. Los clústeres de este laboratorio NUNCA tocan su kubeconfig de siempre: se crean con --kubeconfig ~/ckne-lab/p03/kubeconfig desde el primer comando, y todos los kubectl, helm e istioctl del laboratorio pasan ese archivo y un contexto explícito. Helm se usa con --repo, así que tampoco se agregan repositorios a su configuración. Si ya tiene otros clústeres de kind, este laboratorio no los ve, no los modifica y no los borra; comparten la red de docker kind, y el Paso 3 toma la dirección .250 de esa red. El setup imprime kind get clusters antes de empezar para que lo compruebe.
- Acceso a internet durante todo el laboratorio: kind descarga la imagen del nodo; Helm baja Cilium de helm.cilium.io y MetalLB de metallb.github.io, con sus imágenes de quay.io; el Paso 1 baja los CRD de la Gateway API y de la Inference Extension y el binario istioctl desde github.com, las imágenes de Istio desde docker.io, el simulador desde ghcr.io y el elector desde registry.k8s.io; los Pods y los contenedores bajan busybox, curl, nginx y FRR fijados por digest. El tiempo de 60 minutos cuenta con las imágenes ya descargadas; en la primera corrida suma la descarga.
- VERSIONES FIJADAS, verificadas el 2026-11-22 en esta misma máquina. kind v0.33.0 (mínimo v0.33.0), kubectl v1.37.0, helm v4.3.0 (las opciones que usa el laboratorio son las mismas en Helm 3). Imagen del nodo kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5. Cilium 1.20.5 (paquete de Helm de https://helm.cilium.io). CRD de la Gateway API v1.6.1, canal estándar, y de la Inference Extension v1.0.1 (manifests.yaml de su versión). Istio 1.32.0 con istioctl de https://github.com/istio/istio/releases/download/1.32.0/ (el Paso 1 verifica la huella SHA-256 del archivo) y el perfil minimal. Simulador ghcr.io/llm-d/llm-d-inference-sim:v0.7.1@sha256:74211b5dbf27a867fcefae92067701e0a5fcee827f95156d89718bf3e1bfb845. Elector registry.k8s.io/gateway-api-inference-extension/epp:v1.0.1@sha256:50e96bc704e4823b0b9fef9739fb952a82dcc7f5b8a8f93fecf8fd07ec4b66c9. MetalLB 0.16.2 (paquete de Helm de https://metallb.github.io/metallb). FRR quay.io/frrouting/frr:10.7.1@sha256:e995beaa50fdc9edb35eadcfefa29b7f062cc06f2b812613789b68fa541554d2. busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0, curlimages/curl:8.19.0@sha256:c03110c736db81bbe1be0296f1f1608c81b954b01626bdfb0a8f84e5bd00ff3c y nginx:1.29-alpine@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de. Un tag es mutable y un digest no. Confirme lo que le quedó instalado con kind version, kubectl version, helm version e istioctl version, nunca de memoria.
- Haber leído los Capítulos 10, 11 y 12. Este laboratorio no vuelve a explicar qué es un InferencePool, qué hace una pasarela de salida, cómo anuncia MetalLB una dirección por BGP ni qué es una ServiceExport; le hace operarlos contra clústeres reales y le califica el estado final. Los pasos son dependientes: el 2 necesita el clúster y el grupo del 1; el 3 y el 4 necesitan el clúster ckne-lab3 del 1; el 6 necesita los dos clústeres del 5, y el 7 necesita la malla del 5 y el espacio cartas del 6.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 10: Tres servidores de modelo, un grupo con su elector y dos rutas para comparar el reparto (10 pts)

Objetivo: en el clúster ckne-lab3, en el espacio imprenta, dos réplicas del servidor simulado redactor y una de redactor-ocupado, que publica una cola de 30 peticiones y la caché casi llena; las tres con la etiqueta `grupo=redaccion` y detrás de la Service redactores. Un InferencePool llamado `redaccion` que las elige por esa etiqueta, con su elector (el EPP) llamado elector en el puerto 9002. Una Gateway llamada `portico` de la clase istio, con una Service de tipo ClusterIP, y dos HTTPRoute: por-el-grupo, para grupo.imprenta.example, hacia el InferencePool, y por-la-service, para service.imprenta.example, hacia la Service redactores. Todo con sus sellos en True.

El Capítulo 10 contó por qué una petición a un modelo no es un pasajero corriente: una Service reparte sin mirar a quién, y el elector lee las métricas de cada servidor antes de decidir. Este paso deja las dos decisiones lado a lado, con el mismo servidor saturado en las dos listas. El elector deja escrito en su registro el puntaje que le dio a cada Pod, y ese registro es lo primero que se lee cuando el reparto no cuadra.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es dar por bueno un grupo que existe pero no decide nada, o quitar al servidor saturado para que el reparto se vea bien. La comprobación lo cierra: exige el clúster con tres nodos Ready en v1.37.0, sin kube-proxy ni kindnet, Cilium v1.20.5 con el reemplazo de kube-proxy, el enmascarado BPF y la pasarela de salida activos; los CRD de la Gateway API v1.6.1 y de la Inference Extension; istiod 1.32.0 listo y con ENABLE_GATEWAY_API_INFERENCE_EXTENSION; dos réplicas listas de redactor y una de redactor-ocupado que sigue publicando su cola falsa de 30; el grupo `redaccion` con el selector `grupo=redaccion`, el puerto 8000, el elector en el 9002 y sus dos sellos en True; y las dos rutas con sus sellos en True. Después lanza sondas nuevas que piden a la IP de `portico-istio`: por la ruta del grupo, dieciséis peticiones con 200, ninguna al ocupado y las dos réplicas libres presentes; por la ruta de la Service, veinticuatro peticiones con 200 y al menos una al ocupado, que prueba que sigue vivo. Las líneas de 01-respuesta.txt se comparan con el clúster vivo.

</details>

<details>
<summary>Qué debería ver</summary>

kind create termina con Set kubectl context to kind-ckne-lab3, el rollout de Cilium termina con successfully rolled out y los tres nodos quedan con condition met. Los CRD de la Inference Extension listan inferenceobjectives.inference.networking.x-k8s.io, inferencepools.inference.networking.k8s.io e inferencepools.inference.networking.x-k8s.io; la huella del archivo de istioctl imprime OK e istioctl install termina con su línea de instalación completa. Los tres servidores quedan con condition met, el elector y `portico-istio` terminan con successfully rolled out, y el grupo `redaccion` muestra Accepted=True y ResolvedRefs=True. Por la ruta service las doce peticiones se reparten entre los tres Pods, también redactor-ocupado; por la ruta grupo las doce van a los dos redactor y ninguna al ocupado, todas con 200. Las últimas líneas del registro del elector muestran el puntaje queue 0 y kv 10 para redactor-ocupado frente a 100 y 100 para los otros dos, y prefix 0 para los tres (los textos cortos no alcanzan el bloque mínimo del puntaje de prefijo). Guarde en 01-respuesta.txt las líneas SERVICE_DEL_PORTICO=, POD_QUE_EL_ELECTOR_EVITA= y PUERTO_DEL_ELECTOR=.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 10: El grupo que le manda todo al servidor saturado, leído en el orden del capítulo (10 pts)

Objetivo: que la ruta del grupo vuelva a evitar al servidor saturado sin sacarlo del grupo ni de la Service, después de ubicar la avería que deja inyectar-falla.sh. Entregables: 02-diagnostico.txt con lo que leyó en cada pieza y 02-respuesta.txt.

Una avería que no devuelve errores es la más difícil de ver: todas las peticiones contestan 200 y, sin embargo, el reparto quedó en el peor lugar posible. El orden de lectura que dejó el Capítulo 10 sirve justo aquí. Primero el puntaje del elector (el coordinador del Capítulo 10), que dice entre quiénes eligió; después los extremos que recibió el Envoy de la entrada, que dicen a quiénes podía mandar; solo al final los servidores de modelo. Cuando las dos primeras lecturas cuentan menos candidatos de los que hay en marcha, siga el rastro hasta el objeto que los produce.

<details>
<summary>Pista del verificador (check_hint)</summary>

Los atajos que cierra: borrar, escalar a cero o reetiquetar a redactor-ocupado para que el grupo no tenga a quién elegir mal (el ocupado tiene que seguir con una réplica lista, sus etiquetas app=redactor-ocupado y `grupo=redaccion` y su cola falsa de 30); y llevar la ruta a la Service (por-el-grupo tiene que seguir apuntando al InferencePool `redaccion`). Exige que el grupo termine con los tres servidores en Running, dos redactor y el ocupado, que sus dos sellos estén en True y que el elector esté listo. El archivo 02-diagnostico.txt tiene que ser de esta falla en este clúster: puntajes solo para el ocupado de su clúster y un solo extremo del grupo en el Envoy, con la IP de ese Pod, y tiene que haberse escrito después de inyectada la falla. Una sonda nueva hace dieciséis peticiones por la ruta del grupo (ninguna al ocupado, las dos réplicas libres presentes) y otra hace veinticuatro por la de la Service, donde el ocupado tiene que aparecer.

</details>

<details>
<summary>Qué debería ver</summary>

Corre inyectar-falla.sh, que imprime falla inyectada. EL SINTOMA: las doce peticiones por la ruta del grupo van todas a redactor-ocupado, con 200; nada falla, pero el grupo eligió justo al que tiene la cola llena. El diagnóstico, guardado en 02-diagnostico.txt, lee en el orden del Capítulo 10. 1: el registro del elector solo trae puntajes para redactor-ocupado (queue 100 y kv 10): el elector no tiene a nadie más con quien compararlo. 2: el Envoy de `portico` recibe para el grupo (el clúster de la Service `redaccion-ip-...` en el puerto 54321) un solo extremo, la IP del ocupado en el 8000, mientras la Service redactores sigue con tres. 3: los tres servidores están listos. 4: el grupo elige por app=redactor-ocupado en lugar de `grupo=redaccion`. Después de devolverle al grupo su selector, las veinte peticiones vuelven a repartirse entre los dos redactor libres. Guarde en 02-respuesta.txt las líneas POD_QUE_RECIBIA_TODO=, PODS_PUNTUADOS_DURANTE_LA_FALLA=, OBJETO_CON_LA_FALLA= y CAMPO_CON_LA_FALLA=.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 11: Un turno que sale siempre con la misma dirección, comprobado en el destino (10 pts)

Objetivo: en ckne-lab3, que los Pods del espacio `envios` con la etiqueta turno=noche lleguen al contenedor `ckne-lab3-buzon` (fuera del clúster, en la red kind) con la dirección fija, la .250 del segmento de la red kind, saliendo por ckne-lab3-worker2, que lleva la etiqueta egreso=si y esa dirección en eth0. La política se llama noche-con-ip-fija. Los Pods remitente (turno=noche) y testigo (sin la etiqueta) corren en ckne-lab3-worker. Entregable: 03-respuesta.txt.

El Capítulo 11 dejó un hábito: la dirección de origen se comprueba en el destino, no en la política. Una política aceptada por la API puede no estar haciendo nada, y lo único que no miente es lo que anotó el servidor que recibió la conexión. En kind, la dirección fija es una dirección secundaria en la interfaz de un nodo que es un contenedor, y el `buzon` es otro contenedor en la misma red: el mecanismo es el mismo que con una tarjeta de red real, pero el entorno es más pequeño.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es mirar la política y darla por cumplida, o poner a los Pods en la red del nodo. La comprobación lo cierra: exige la CiliumEgressGatewayPolicy noche-con-ip-fija con un solo selector (turno=noche en `envios`), el `buzon` /32 entre sus destinos y la dirección fija como egressIP; un nodeSelector que elija solo a ckne-lab3-worker2, que tiene la dirección fija en eth0; y a remitente (con turno=noche) y testigo (sin esa etiqueta) en Running en ckne-lab3-worker, sin hostNetwork. Después lo comprueba en el destino: le hace pedir a cada uno una ruta única y busca esa ruta en el registro del `buzon`, donde remitente tiene que llegar con la dirección fija y testigo con la IP de su nodo; lanza dos sondas nuevas en el mismo trabajador, una con la etiqueta y otra sin ella, con el mismo resultado; y lee en vivo la tabla de la pasarela en el agente de ckne-lab3-worker2.

</details>

<details>
<summary>Qué debería ver</summary>

El comando imprime la red kind (172.18.0.0/16 en esta máquina; en la suya puede ser otra) y la dirección fija, que es la .250 del segmento de su gateway. El contenedor `ckne-lab3-buzon` queda en la red kind con una IP propia, y los Pods remitente y testigo quedan con condition met en ckne-lab3-worker. Antes de la política, el registro del `buzon` anota las dos peticiones con la IP de ckne-lab3-worker: el enmascarado de Cilium cambió la IP del Pod por la de su nodo. ckne-lab3-worker2 muestra dos direcciones en eth0, la suya y la fija, y la política se crea. Después, el `buzon` anota a remitente con la dirección fija y a testigo otra vez con la IP de ckne-lab3-worker: la política actúa por etiqueta, no por nodo. El agente de Cilium de ckne-lab3-worker2 lista una entrada con la IP de remitente, el `buzon` /32 y la dirección fija como Egress IP. Las dos curl imprimen 404, que es del nginx (la ruta pedida no existe): lo que interesa es quién llegó. Guarde en 03-respuesta.txt las líneas IP_FIJA=, ORIGEN_DEL_TESTIGO_EN_EL_DESTINO= y NODO_PUERTA=.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 11: Una dirección anunciada por BGP, leída en la tabla del enrutador vecino (10 pts)

Objetivo: en ckne-lab3, MetalLB 0.16.2 en metallb-system, con un IPAddressPool llamado rango-lab (198.51.100.10-198.51.100.20), un BGPPeer llamado frontera (AS 64601 del clúster, AS 64600 del vecino) hacia el contenedor FRR ckne-lab3-frontera y un BGPAdvertisement de ese rango; y la Service vitrina, de tipo LoadBalancer, en el espacio `envios` con dos réplicas que contestan su nombre. Entregable: 04-respuesta.txt.

La segunda mitad del hábito del Capítulo 11: una ruta anunciada se comprueba en la tabla del enrutador vecino, no en el estado de la Service. La Service puede mostrar una IP externa que nadie fuera del clúster sabe cómo alcanzar. El vecino de este paso acepta sesiones de cualquier dirección de la red kind, así que no hace falta conocer de antemano las IP de los nodos; cada nodo que anuncia la dirección aparece como un salto en su tabla. 198.51.100.0/24 es un bloque reservado para documentación (TEST-NET-2), así que no choca con ninguna red real.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es fiarse de la IP que muestra la Service, o escribir a mano una ruta estática en el vecino. La comprobación lo cierra: exige el controlador de MetalLB v0.16.2 listo; el rango rango-lab con 198.51.100.10-198.51.100.20, el BGPPeer frontera con los AS 64601 y 64600 hacia la IP del contenedor ckne-lab3-frontera, y un anuncio de ese rango; la Service vitrina de tipo LoadBalancer con dos réplicas listas y una IP de ese rango asignada por MetalLB. Después lee la tabla del vecino: la ruta /32 de esa IP tiene que haberse aprendido por BGP, estar elegida y tener como saltos los dos trabajadores, y en la configuración del FRR no puede haber ninguna ruta estática. Por último pide la IP desde la frontera y exige que conteste una réplica viva de vitrina.

</details>

<details>
<summary>Qué debería ver</summary>

Helm instala MetalLB (puede imprimir un aviso unrecognized format "cidr", que no impide la instalación) y los Pods de metallb-system quedan en Running: el controlador, un speaker y un frr-k8s por nodo y el statuscleaner. El contenedor ckne-lab3-frontera queda en la red kind con su IP, y se crean rango-lab, frontera y anuncio-lab. vitrina recibe 198.51.100.10, la primera del rango. En el resumen de BGP de la frontera aparecen tres vecinos dinámicos (marcados con *) del AS 64601, uno por nodo: el plano de control con 0 prefijos recibidos y los dos trabajadores con 1, porque kind marca el plano de control con la etiqueta node.kubernetes.io/exclude-from-external-load-balancers. La tabla de rutas muestra B>* 198.51.100.10/32 con dos saltos, uno por trabajador, y el wget desde la frontera devuelve el nombre de una réplica de vitrina. Guarde en 04-respuesta.txt las líneas IP_ANUNCIADA=, SALTOS_HACIA_LA_IP= y AS_DEL_CLUSTER=.

</details>

```bash
./04-step.sh
./04-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 5. Cap. 12: Dos clústeres que se reconocen en una malla (10 pts)

Objetivo: dos clústeres kind, ckne-lab3-uno (Pods 10.31.0.0/16, Services 10.32.0.0/16) y ckne-lab3-dos (Pods 10.41.0.0/16, Services 10.42.0.0/16), con un plano de control y un trabajador cada uno, sin kube-proxy, con Cilium 1.20.5 de nombre igual al clúster e id 1 y 2, unidos por Cluster Mesh a través de un clustermesh-apiserver en NodePort 32379, con la misma autoridad certificadora, el API de MCS activo y CoreDNS configurado para clusterset.local. Entregable: 05-respuesta.txt.

El Capítulo 12 mostró que una malla tiene dos niveles que conviene leer por separado: el agente de Cilium de cada nodo y KVStoreMesh, que guarda dentro del clustermesh-apiserver una copia local de lo que publica el otro clúster. Los agentes hablan con esa copia, no con el otro clúster. Este paso deja los dos niveles en 1/1, para que el próximo los vea separarse. Los rangos de Pods no se pisan entre clústeres: es una condición de la malla.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es dar por unida una malla porque los dos Cilium están instalados. La comprobación lo cierra: en cada clúster exige dos nodos Ready con su rango de Pods (10.31 en uno, 10.41 en dos), sin kube-proxy, Cilium v1.20.5 listo en los dos nodos con el nombre ckne-lab3-uno o ckne-lab3-dos y el id 1 o 2, el reemplazo de kube-proxy, el clustermesh-apiserver listo detrás de una Service NodePort en el 32379, el CRD de ServiceImport y la línea multicluster clusterset.local en el Corefile. Después pregunta en vivo: el agente de Cilium de cada lado tiene que decir 1/1 y KVStoreMesh de cada lado tiene que decir 1/1 con el otro clúster ready. Los dos clústeres tienen que compartir la misma autoridad certificadora. Las líneas de 05-respuesta.txt se comparan con lo esperado.

</details>

<details>
<summary>Qué debería ver</summary>

Los dos kind create terminan con Set kubectl context to kind-ckne-lab3-uno y kind-ckne-lab3-dos. Helm puede imprimir un aviso de que clustermesh.config.clusters es una tabla y se ignora el valor vacío por defecto: es inofensivo, los valores del archivo mandan. Se crea secret/cilium-ca en dos, los dos rollouts de Cilium y de clustermesh-apiserver terminan con successfully rolled out, y en uno a dos minutos cada agente dice ClusterMesh: 1/1 remote clusters ready. KVStoreMesh de cada lado dice 1/1 y nombra al otro clúster como ready, con 2 nodos y 0 servicios. El Corefile de uno trae clusterset.local en la línea kubernetes y la línea multicluster clusterset.local que escribió la configuración automática de CoreDNS. Guarde en 05-respuesta.txt las líneas ID_DE_UNO=, ID_DE_DOS=, PUERTO_DE_LA_MALLA= y ZONA_ENTRE_CLUSTERES=.

</details>

```bash
./05-step.sh
./05-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 6. Cap. 12: La misma Service en los dos clústeres, y lo que dicen el agente y KVStoreMesh en una caída (10 pts)

Objetivo: en los dos clústeres, el espacio cartas con un Deployment relevo de dos réplicas que contestan el nombre de su clúster, su Service relevo (puerto 80) y una ServiceExport relevo; el Pod explorador en cartas de uno. Después, una caída controlada: el clustermesh-apiserver de dos en cero réplicas mientras lee el agente y KVStoreMesh de uno y el reparto, y luego de vuelta a una réplica. Entregables: 06-caida.txt y 06-respuesta.txt.

Las dos comprobaciones que el Capítulo 12 dejó para esta práctica están aquí. La primera: sin su ServiceExport, un clúster no aporta Pods al nombre del conjunto, aunque tenga la misma Service. La segunda: el agente de Cilium y KVStoreMesh pueden decir cosas distintas a la vez, y esa diferencia es el primer dato. Esta caída es otra que la del capítulo: los nodos de dos siguen encendidos y solo se apaga el servidor que publica su estado, así que se ve cuánto aguanta la copia local de uno.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es exportar en un solo clúster, o escribir 06-caida.txt sin haber apagado nada. La comprobación lo cierra: en los dos clústeres exige la Service relevo con el selector app=relevo, dos réplicas listas, su ServiceExport con Valid y Ready en True, una ServiceImport que nombra a los dos clústeres y el agente en 1/1. La caída tiene que haber ocurrido y terminado: el Deployment clustermesh-apiserver de dos tiene que haber cambiado de réplicas (su generación) y estar otra vez con una lista, y KVStoreMesh de uno tiene que contar al menos una reconexión con dos, ya en ready. 06-caida.txt tiene que traer la línea 1/1 del agente, la línea 0/1 de KVStoreMesh con ckne-lab3-dos not-ready y respuestas de dos durante la caída. Una sonda nueva en uno hace veinte peticiones al nombre clusterset.local y tienen que contestar los dos clústeres.

</details>

<details>
<summary>Qué debería ver</summary>

En cada clúster se crean cartas, relevo y su Service, y el rollout termina con dos réplicas. explorador queda con condition met en uno. Al exportar en los dos, la ServiceImport relevo de uno es de tipo ClusterSetIP, con una IP del rango de Services de uno (10.32) y los dos clústeres en su lista. Las veinte peticiones al nombre relevo.cartas.svc.clusterset.local se reparten entre ckne-lab3-uno y ckne-lab3-dos (en la corrida registrada, 11 y 7, más dos líneas sin-respuesta con wget: download timed out: justo después de aparecer la ServiceImport, un par de pedidos hacia dos agotaron su plazo de dos segundos; la sonda del verificador, más tarde, exige las veinte respuestas). Al escalar a cero el clustermesh-apiserver de dos, 06-caida.txt registra la hora y, al mismo tiempo, ClusterMesh: 1/1 remote clusters ready en el agente de uno y KVStoreMesh: 0/1 remote clusters ready en uno, con ckne-lab3-dos como not-ready y sus datos todavía en la copia; y el reparto sigue contestando desde los dos clústeres, porque los Pods de dos siguen vivos y uno conserva sus extremos. Al volver a una réplica, KVStoreMesh de uno vuelve a 1/1 y su contador de reconexiones con dos ya no está en 0, y el reparto sigue entre los dos. Guarde en 06-respuesta.txt las líneas AGENTE_DE_UNO_EN_LA_CAIDA=, KVSTOREMESH_DE_UNO_EN_LA_CAIDA= y DOS_SIGUIO_ATENDIENDO= (si o no).

</details>

```bash
./06-step.sh
./06-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 7. Cap. 12: Una Service que solo aporta un clúster, solo con el objetivo (punto sin resolver) (10 pts)

El examen no le da el comando: le da una tarea escrita como objetivo y un tiempo. Este paso es esa situación en pequeño. Todo lo que necesita lo tiene del Paso 6 y del Capítulo 12: cómo se exporta una Service, qué nombre tiene en el conjunto y cómo se lee qué clúster aporta Pods. Lo que no tiene es una receta, ni la ficha a mano: el setup la dejó en un archivo que cambia en cada corrida, como el dato que el examen pone en el enunciado y que usted tiene que usar para alcanzar el objetivo. Tampoco hay archivo de respuesta: lo que se califica es el estado de los dos clústeres.

El objetivo está escrito como comentario al final del cmd del paso. Léalo con calma, escriba en una línea cada condición que tiene que cumplirse, y arme el estado final de a una. Si se atasca, el cmd del paso solo imprime la ficha de la corrida: las señales están en el check_hint, que dice qué atajos están cerrados pero no cómo se hace.

<details>
<summary>Pista del verificador (check_hint)</summary>

Este es el punto sin resolver: la comprobación falla con el estado guiado de los Pasos 1 a 6 porque consigna ni siquiera existe, hasta que usted lo resuelva. Los atajos que cierra: servir la ficha desde uno (en uno no puede haber ni ServiceExport ni Service consigna, la ServiceImport tiene que nombrar solo a ckne-lab3-dos y cada agente de uno tiene que repartir hacia IP de Pods de dos, 10.41.0.0/16, entre ellas la de un extremo listo de consigna); una Service sin selector o con una lista de extremos hecha a mano en dos (la lista tiene que traer un Pod listo de resguardo que la Service elige por su selector); y editar la ficha (se compara con una huella que el setup guardó aparte). Lo decisivo es el estado final: una sonda nueva en uno, en el espacio cartas, que resuelve el nombre del conjunto a la IP de la ServiceImport y recibe la ficha completa cinco veces. Para avanzar sin solución publicada: parta del objetivo, escriba una condición por línea y, cuando algo no funcione, lea las condiciones y el estado de cada objeto: dicen qué falta.

</details>

<details>
<summary>Qué debería ver</summary>

No se publica la secuencia de comandos de este paso: es el punto sin resolver. El estado final correcto: en ckne-lab3-dos, en el espacio resguardo, hay Pods que responden la ficha de esta corrida en la raíz, detrás de una Service consigna de tipo ClusterIP con selector y puerto 80, exportada con su ServiceExport en Valid y Ready; en ckne-lab3-uno no hay ni ServiceExport ni Service consigna, la ServiceImport consigna nombra solo a ckne-lab3-dos y los agentes de uno reparten hacia IP de Pods de dos; y una sonda nueva en el espacio cartas de uno resuelve consigna.resguardo.svc.clusterset.local a la IP de esa ServiceImport y recibe, en cinco pedidos seguidos, la ficha completa. Con lo que practicó en el Paso 6 y lo que leyó en el Capítulo 12 hay todo lo necesario.

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

- **Síntoma (step 1):** El elector se queda en 0/1 y su registro dice cannot list resource
  **Qué hacer:** Al elector le falta un permiso de lectura. Compare las reglas del Role elector con el recurso que nombra el registro; el elector v1.0.1 lee el grupo, los Pods y los objetivos.

- **Síntoma (step 1):** La ruta del grupo contesta 500
  **Qué hacer:** La entrada no alcanza al elector. Mire que el Deployment elector esté listo y que exista la DestinationRule elector-tls: la entrada habla con el elector por TLS.

- **Síntoma (step 2):** istioctl proxy-config endpoint no muestra ninguna línea de `redaccion-ip`
  **Qué hacer:** Use el istioctl que bajó el Paso 1 (./bin/istioctl en ~/ckne-lab/p03) con --kubeconfig y --context, y apunte a `deploy/portico-istio` en el espacio imprenta: es el Envoy de la entrada, no el de otro Pod.

- **Síntoma (step 2):** Después de reparar, la ruta del grupo todavía manda algo al ocupado
  **Qué hacer:** El elector necesita unos segundos para volver a leer las métricas de los servidores después de la reparación. Espere quince segundos y repita; si sigue, lea otra vez el registro del elector y cuente cuántos Pods puntúa.

- **Síntoma (step 3):** docker exec ... ip addr add falla con File exists
  **Qué hacer:** La dirección ya está en eth0 de ckne-lab3-worker2, de un intento anterior. Compruébelo con `docker exec ckne-lab3-worker2 ip -4 -o addr show eth0` y siga con el resto del paso.

- **Síntoma (step 3):** El `buzon` sigue anotando a remitente con la IP del nodo
  **Qué hacer:** Lea la entrada en el agente de ckne-lab3-worker2 con `cilium-dbg bpf egress list`. Si no aparece la IP de remitente, mire sus etiquetas y el espacio que nombra la política; si aparece con Egress IP 0.0.0.0, la dirección fija no está en eth0 de ese nodo.

- **Síntoma (step 4):** vitrina se queda con EXTERNAL-IP en pending
  **Qué hacer:** MetalLB no tiene un rango del que tomar la dirección o su controlador no está listo. Mire `kubectl -n metallb-system get ipaddresspool` y los eventos de la Service con describe.

- **Síntoma (step 4):** El resumen de BGP de la frontera no muestra vecinos
  **Qué hacer:** Las sesiones tardan unos segundos. Si después de un minuto siguen sin aparecer, compare el peerAddress del BGPPeer con la IP del contenedor (`docker inspect ckne-lab3-frontera`) y el rango de `bgp listen range` en frontera/frr.conf con la red kind.

- **Síntoma (step 5):** El agente se queda en 0/1 remote clusters ready
  **Qué hacer:** Lo más frecuente es la autoridad certificadora: el secreto cilium-ca tiene que copiarse de uno a dos antes de instalar Cilium en dos. Si lo copió después, desinstale Cilium en dos con helm uninstall, vuelva a copiar el secreto y repita la instalación.

- **Síntoma (step 5):** `kind create cluster` falla en el segundo o el tercer clúster con too many open files
  **Qué hacer:** Es el límite de inotify del anfitrión, compartido por los siete nodos. Suba fs.inotify.max_user_instances con sysctl (el setup imprime el valor actual), borre el clúster a medias con kind delete cluster --name <nombre> --kubeconfig ~/ckne-lab/p03/kubeconfig y repita.

- **Síntoma (step 6):** La ServiceImport de uno nombra un solo clúster
  **Qué hacer:** Falta la ServiceExport en el otro clúster, o todavía no llegó. Mire `kubectl -n cartas get serviceexport relevo` en cada contexto y sus condiciones; la lista de la ServiceImport cambia a los pocos segundos.

- **Síntoma (step 6):** KVStoreMesh de uno no baja de 1/1 durante la caída
  **Qué hacer:** El Pod del clustermesh-apiserver de dos todavía no terminó. Espere a que no quede ninguno con `kubectl -n kube-system get pods -l k8s-app=clustermesh-apiserver` en dos; el bucle del paso espera a que KVStoreMesh deje de decir 1/1 antes de escribir 06-caida.txt.

- **Síntoma (step 7):** Desde uno, el nombre clusterset.local de consigna no resuelve
  **Qué hacer:** Mire la ServiceExport en dos y sus condiciones, y busque la ServiceImport consigna en uno, como hizo con relevo en el Paso 6. Si la de dos está en Valid y Ready y en uno no hay nada, relea el Capítulo 12 y verifique cada condición del objetivo en el clúster donde la está mirando.

- **Síntoma (step 7):** Mi Service responde la ficha pero la comprobación dice que no
  **Qué hacer:** Compare lo que responde con el contenido de ~/ckne-lab/p03/ficha-de-la-consigna.txt: un salto de línea al final no importa, pero cualquier otro carácter sí. Mire que la Service esté en dos y no en uno, que tenga selector y que su ServiceExport exista solo en dos.

## Para ir más lejos

- Repita el Paso 1 con un texto de más de 64 caracteres, el mismo en ocho peticiones seguidas por la ruta del grupo, y mire en el registro del elector cómo cambia el puntaje prefix. Explique por qué el reparto se pega a un solo Pod y qué ganaría un servidor de modelo real con eso.
- En el Paso 4, quite la etiqueta node.kubernetes.io/exclude-from-external-load-balancers del plano de control de ckne-lab3 y vuelva a leer el resumen de BGP de la frontera. Cuente los saltos de la ruta /32 y explique qué cambió y por qué kind pone esa etiqueta.

## Referencias

- Gateway API Inference Extension project, overview and the InferencePool API type. The pool, its selector, targetPorts and endpointPickerRef used in Steps 1 and 2. https://gateway-api-inference-extension.sigs.k8s.io/ and https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepool/
- Gateway API Inference Extension project, v1.0.1 release and its RBAC chart template. The manifests.yaml CRDs and the permissions of the picker used in Step 1. https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/tag/v1.0.1 and https://github.com/kubernetes-sigs/gateway-api-inference-extension/blob/v1.0.1/config/charts/inferencepool/templates/rbac.yaml
- Istio Project, Gateway API Inference Extension task. The two pilot settings, the gatewayClassName istio and the DestinationRule toward the picker used in Step 1. https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api-inference-extension/
- llm-d project, llm-d-inference-sim v0.7.1 README. The --fake-metrics option and the x-inference-pod header used in Steps 1 and 2. https://github.com/llm-d/llm-d-inference-sim/blob/v0.7.1/README.md
- Cilium Project, Egress Gateway (v1.20). The CiliumEgressGatewayPolicy, its podSelector, destinationCIDRs and egressGateway fields, and cilium-dbg bpf egress list, used in Step 3. https://docs.cilium.io/en/v1.20/network/egress-gateway/egress-gateway/
- Cilium Project, Kubernetes without kube-proxy and Masquerading (v1.20). kubeProxyReplacement and bpf.masquerade, set in Step 1 and observed at the destination in Step 3. https://docs.cilium.io/en/v1.20/network/kubernetes/kubeproxy-free/ and https://docs.cilium.io/en/v1.20/network/concepts/masquerading/
- MetalLB Project, Configuration and the v0.16.2 release. IPAddressPool, BGPPeer and BGPAdvertisement used in Step 4. https://metallb.io/configuration/ and https://github.com/metallb/metallb/releases/tag/v0.16.2
- FRRouting Project, BGP. The bgp listen range dynamic neighbors and the show bgp summary and show ip route commands used in Step 4. https://docs.frrouting.org/en/latest/bgp.html
- IETF, RFC 5737, IPv4 Address Blocks Reserved for Documentation. The 198.51.100.0/24 block (TEST-NET-2) used in Step 4. https://www.rfc-editor.org/rfc/rfc5737.txt
- Cilium Project, Setting up Cluster Mesh and Troubleshooting (v1.20). `cluster.name`, `cluster.id`, the shared CA, the clustermesh-apiserver and `kvstoremesh-dbg status`, used in Steps 5 and 6. https://docs.cilium.io/en/v1.20/network/clustermesh/setup/ and https://docs.cilium.io/en/v1.20/operations/troubleshooting/
- Cilium Project, Multi-Cluster Services API (v1.20). clustermesh.mcsapi, CoreDNS auto-configuration, ServiceExport and ServiceImport, used in Steps 5, 6 and 7. https://docs.cilium.io/en/v1.20/network/clustermesh/mcsapi/
- Kubernetes SIG Multicluster, Multicluster Services API concepts. ServiceExport, ServiceImport and the clusterset.local name used in Steps 6 and 7. https://multicluster.sigs.k8s.io/concepts/multicluster-services-api/
- Cilium Project, Installation using kind (v1.20). The kind configuration with the default CNI and kube-proxy disabled, used in Steps 1 and 5. https://docs.cilium.io/en/v1.20/installation/kind/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
