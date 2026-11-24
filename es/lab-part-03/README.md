# Parte III - Laboratorio: una cabina con su lista de extremos, el despachador que la copia en cada nodo, un directorio que deja de contestar y una entrada con la Gateway API

- Tiempo: 60 min
- Puntos: 60

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solamente el objetivo y el entregable, y la secuencia de comandos del paso vive en el campo cmd para que la revele después de haber intentado por su cuenta. La excepción es el Paso 6: ese solo declara el objetivo, no hay comando publicado en ningún lado del repositorio, y su comprobación depende de una ficha, un nombre de anfitrión y una ruta distintos en cada corrida. Qué se construye: el Paso 1 monta el clúster ckne-lab2 (un plano de control, dos trabajadores, Calico v3.33.0) y el espacio cabina con el Deployment meteo de tres réplicas con sonda de readiness, su Service y su EndpointSlice (Capítulo 6). El Paso 2 abre una Service NodePort en un puerto fijo, la prueba desde la máquina anfitriona y sigue esa misma conexión por las reglas que kube-proxy escribió en el nodo y por la anotación que quedó en conntrack (Capítulos 6 y 7). El Paso 3 corre inyectar-falla.sh, un guion que rompe a ciegas una pieza del camino de los nombres: su contenido va codificado a propósito, como una venda de cortesía y no como un secreto real, y la solución está al final en el archivo de respuestas; con nslookup, la EndpointSlice y las reglas del nodo hay que ubicar dónde se rompe (Capítulos 6, 7 y 8). El Paso 4 repara la causa y no el síntoma: la comprobación exige que el Corefile, la IP del directorio y la configuración DNS de los Pods sigan como estaban (Capítulo 8). El Paso 5 instala la Gateway API v1.6.1 y Istio 1.32.0, levanta la entrada rampa y una HTTPRoute hacia meteo (Capítulo 9). El Paso 6 es el examen en miniatura: una ruta que cruza de espacio con datos que cambian en cada corrida, sin comando publicado.

## Prerrequisitos

- Una máquina Linux con kind, kubectl, docker, jq, curl, tar, sha256sum y base64 en el PATH, y con al menos 6 GB de RAM libres para tres nodos con Istio. El laboratorio crea su propio clúster kind llamado ckne-lab2 y lo elimina en el teardown.
- AISLAMIENTO. El clúster de este laboratorio NUNCA toca su kubeconfig de siempre: se crea con --kubeconfig ~/ckne-lab/p02/kubeconfig desde el primer comando, y todos los kubectl e istioctl del laboratorio pasan --kubeconfig explícito. Si ya tiene otros clústeres de kind, este laboratorio no los ve, no los modifica y no los borra. El setup imprime kind get clusters antes de empezar para que lo compruebe.
- Acceso a internet durante todo el laboratorio: kind descarga la imagen del nodo; el Paso 1 baja el manifiesto de Calico desde raw.githubusercontent.com y sus imágenes de quay.io; el Paso 5 baja los CRD de la Gateway API y el binario istioctl desde github.com, y las imágenes de Istio desde docker.io; los Pods bajan una imagen de busybox fijada por digest desde docker.io.
- VERSIONES FIJADAS, verificadas el 2026-11-19 en esta misma máquina. kind v0.33.0 (mínimo v0.33.0). kubectl v1.37.0. Imagen del nodo kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5. Calico v3.33.0 con el manifiesto https://raw.githubusercontent.com/projectcalico/calico/v3.33.0/manifests/calico.yaml. CRD de la Gateway API v1.6.1, canal estándar, de https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml (la versión que instala la tarea de Gateway API de Istio 1.32). Istio 1.32.0 con istioctl de https://github.com/istio/istio/releases/download/1.32.0/ (el Paso 5 verifica la huella SHA-256 del archivo) y el perfil minimal. Imagen de los Pods busybox:1.37.0@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0. Un tag es mutable y un digest no. Confirme lo que le quedó instalado con kind version, kubectl version e istioctl version, nunca de memoria.
- Haber leído los Capítulos 6, 7, 8 y 9. Este laboratorio no vuelve a explicar qué es una EndpointSlice, cómo escribe kube-proxy sus reglas, cómo resuelve un Pod un nombre ni qué es una HTTPRoute; le hace operarlos contra un clúster real y le califica el estado final. Los pasos son dependientes: el 2 y el 3 necesitan el clúster y meteo del 1, el 4 necesita la falla del 3, y el 5 y el 6 necesitan el clúster del 1 con el directorio ya reparado en el 4.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 6: La cabina con tres réplicas listas, su Service y la lista de extremos que la respalda (10 pts)

El Capítulo 6 separó dos cosas que en la práctica se confunden: la Service es un número fijo que anuncia un puerto, y la EndpointSlice es la lista de quién atiende en ese momento y en qué puerto real. Este paso deja las dos a la vista. Fíjese en que la Service apunta a un puerto con nombre (web) y no a un número: si mañana el contenedor cambia de puerto, la Service no se toca. La sonda de readiness es la que decide quién entra en la lista, y es la razón de que el rollout espere a que cada réplica conteste antes de darla por lista.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es dar por buena una Service que existe pero no tiene a nadie detrás. La comprobación lo cierra: exige el clúster con tres nodos Ready en v1.37.0, Calico v3.33.0 y sin kindnet; el Deployment meteo con tres réplicas listas y una sonda de readiness; la Service meteo de tipo ClusterIP con el selector app=meteo y el puerto 80; el Pod piloto en Running; y una EndpointSlice con tres extremos ready=true y el puerto 8080. Después lanza una sonda nueva que le pide a la IP de la Service (no al nombre, para no depender del DNS) y exige que conteste una de las réplicas vivas de meteo. Las líneas de 01-respuesta.txt se comparan con el clúster vivo.

</details>

<details>
<summary>Qué debería ver</summary>

El kind create termina con Set kubectl context to kind-ckne-lab2. El rollout status de calico-node termina con successfully rolled out, el wait deja los tres nodos con condition met y CoreDNS queda desplegado. Después se crean el espacio cabina, el Deployment meteo, la Service meteo y el Pod piloto, y el rollout de meteo termina con sus tres réplicas disponibles. get svc muestra meteo como ClusterIP con una IP del rango de Services (10.96.0.0/16 en kind) y el puerto 80/TCP. La EndpointSlice lista tres extremos, cada uno con una IP de 192.168.0.0/16, el nombre de su Pod meteo y ready=true; sus puertos dicen name http y port 8080: la Service anuncia el 80, pero la lista guarda el puerto real del contenedor, que la Service nombró como web. El wget de piloto devuelve el nombre de una de las réplicas. Guarde en 01-respuesta.txt las líneas CLUSTER_IP_DE_METEO=, EXTREMOS_LISTOS= y PUERTO_DE_LOS_EXTREMOS= con lo que acaba de ver.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 6 y 7: Una puerta hacia la calle en un puerto fijo, la libreta del despachador y la conversación anotada (10 pts)

Una NodePort es la misma Service con una puerta más: un puerto que se abre en todos los nodos y que lleva a la misma lista de extremos. Lo interesante del Capítulo 7 es quién abre esa puerta. No es un proceso que escucha en el 30380: es kube-proxy, que escribió reglas en el núcleo de cada nodo, y el núcleo traduce el destino del paquete al vuelo. Por eso el puerto responde también en un nodo que no tiene ningún Pod de meteo. Las reglas DNAT con el comentario de la Service son la libreta del despachador; conntrack es lo que el núcleo anotó de cada conversación ya despachada, y es el lugar donde se ve a qué Pod fue a parar una conexión concreta.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es abrir el puerto 30380 por fuera de kube-proxy, con hostNetwork o hostPort en los Pods de meteo, o contar las reglas de memoria. La comprobación exige una Service NodePort llamada meteo-calle con el selector app=meteo y el nodePort 30380, ningún Pod de meteo con hostNetwork ni hostPort, y una respuesta de una réplica viva desde la máquina anfitriona en los DOS trabajadores. Lee el modo de kube-proxy de su ConfigMap y cuenta en el nodo las reglas DNAT de cabina/meteo:http, que tienen que ser tantas como extremos listos tiene la lista. El archivo 02-conntrack.txt tiene que traer una conversación hacia el 30380 cuya respuesta salió por el puerto 8080 de la IP de una réplica viva de meteo, y además la comprobación hace su propia llamada al 30380 de ckne-lab2-worker y lee conntrack en vivo en ese nodo, así que un archivo escrito a mano no alcanza.

</details>

<details>
<summary>Qué debería ver</summary>

El apply crea service/meteo-calle. Los dos curl desde la máquina anfitriona, uno a la IP de cada trabajador en el puerto 30380, devuelven el nombre de una réplica de meteo: el puerto de nodo se abre en todos los nodos, tenga o no un Pod de meteo. El grep de la ConfigMap de kube-proxy imprime mode: iptables. El grep de iptables-save en ckne-lab2-worker muestra tres reglas DNAT con el comentario cabina/meteo:http, una por extremo, cada una hacia una IP de Pod en el puerto 8080: es la lista del Paso 1 copiada en la libreta del nodo. Por último, conntrack lista una o más conexiones TIME_WAIT con dport=30380 cuya mitad de respuesta viene de una IP de Pod con sport=8080: la traducción que el despachador anotó para esa conversación. Guarde en 02-respuesta.txt las líneas MODO_DE_KUBE_PROXY=, CADENAS_DE_EXTREMO= y PUERTO_DE_NODO=.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 6, 7 y 8: El directorio que deja de contestar, y dónde se corta el camino de un nombre (10 pts)

Un nombre que no resuelve es la queja más vaga de todas, y por eso conviene partir el camino en tramos, como en el Capítulo 8. El Pod pregunta a la IP que su resolv.conf le dio; esa IP es una Service; la Service tiene una lista de extremos; kube-proxy copió esa lista en las reglas del nodo; y al final hay un Pod de CoreDNS escuchando en un puerto. Preguntarle directo al Pod de CoreDNS se salta todos los tramos del medio: si ahí contesta, el directorio está sano y el problema está entre el cliente y él. La palabra exacta del error también es una señal. Un plazo agotado, un NXDOMAIN y un rechazo dicen cosas distintas: el NXDOMAIN es una respuesta de alguien que sabe que el nombre no existe; el rechazo es el núcleo de la máquina destino diciendo que en ese puerto no escucha nadie.

<details>
<summary>Pista del verificador (check_hint)</summary>

Esta comprobación vale en dos momentos: con la falla puesta y después de repararla. Exige que la marca de que la falla se aplicó exista y que 03-diagnostico.txt sea evidencia de esta corrida: el rechazo hacia la IP viva de kube-dns, una respuesta correcta desde una IP de Pod con la IP viva de meteo, el puerto dns UDP de la Service apuntando a 5353 y la regla DNAT de kube-system/kube-dns:dns hacia ese puerto. Después mide el estado real y lo cruza con la causa: si la Service todavía apunta al puerto equivocado, una sonda nueva NO puede resolver meteo; si ya se reparó, SÍ puede. Una mezcla de las dos cosas falla, de modo que no sirve fingir el síntoma ni ocultarlo. El atajo de adivinar sin mirar se cierra con las líneas de 03-respuesta.txt, que resumen lo que la evidencia dice.

</details>

<details>
<summary>Qué debería ver</summary>

ANTES DE LA FALLA, nslookup contesta desde el servidor 10.96.0.10 con la IP de la Service meteo. Corre inyectar-falla.sh, que imprime falla inyectada. DESPUES DE LA FALLA, el wget por nombre termina con bad address: el nombre ya no se resuelve. El diagnóstico, guardado en 03-diagnostico.txt, separa las piezas. Por la Service del directorio, nslookup imprime dos líneas: write to '10.96.0.10': Connection refused, que es la causa, y ;; connection timed out; no servers could be reached, que es su resumen al quedarse sin servidores. No es un NXDOMAIN ni un plazo agotado por silencio: alguien rechazó el paquete. Directo a la IP de un Pod de CoreDNS, la misma pregunta contesta bien: CoreDNS está sano. La Service kube-dns muestra que su puerto dns UDP 53 apunta a 5353, mientras dns-tcp sigue en 53; la lista de extremos repite ese 5353 para dns; y la libreta del nodo tiene las reglas DNAT de kube-system/kube-dns:dns hacia IP de Pod en el puerto 5353, donde CoreDNS no escucha. Guarde en 03-respuesta.txt las líneas SERVICIO_CON_FALLA=, PROTOCOLO_QUE_FALLA=, PUERTO_EN_LA_LISTA=, PUERTO_DE_COREDNS= y RESPUESTA_DEL_CLIENTE= (rechazada, agotada o nxdomain).

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 8: Reparar el directorio por la causa, sin tocar el Corefile ni la IP que todos los Pods conocen (10 pts)

Hay dos maneras de hacer que vuelva a funcionar y solo una repara. La otra cambia el resto del aeropuerto para que encaje con la pieza rota: mover CoreDNS a otro puerto, inventar otra IP para el directorio o escribirle a mano un servidor a cada Pod. Cada una de esas deja una diferencia silenciosa que alguien va a encontrar meses después. La regla de oficio es la misma del Capítulo 8: el directorio tiene una dirección que todo el clúster conoce, y el kubelet la escribe en el resolv.conf de cada Pod que nace; lo que se arregla es el tramo que se desvió, y se demuestra con un Pod nuevo, que no carga ninguna excepción.

<details>
<summary>Pista del verificador (check_hint)</summary>

Los atajos que cierra: poner CoreDNS a escuchar en 5353 para que coincida con la Service rota (el Corefile se compara con la huella que inyectar-falla.sh guardó antes de romper nada); recrear kube-dns con otra IP (la IP tiene que seguir siendo 10.96.0.10, la que el kubelet de los tres nodos escribe en cada Pod); y darle a piloto un dnsConfig con la IP de un Pod de CoreDNS (piloto tiene que seguir con dnsPolicy ClusterFirst y sin dnsConfig, y además la comprobación lanza una sonda nueva con la configuración por defecto). Exige los tres puertos de kube-dns hacia 53, 53 y 9153 con el selector intacto, la lista de extremos con dns UDP 53, las dos réplicas de CoreDNS listas, ninguna regla DNAT hacia 5353 en los nodos, y que la sonda resuelva meteo desde 10.96.0.10 y reciba respuesta de una réplica viva.

</details>

<details>
<summary>Qué debería ver</summary>

El primer comando lista los puertos que declara el contenedor de CoreDNS: dns UDP 53, dns-tcp TCP 53 y metrics TCP 9153, más liveness-probe TCP 8080 y readiness-probe TCP 8181, que usan sus sondas. El segundo muestra la Service con el dns UDP desviado a 5353. El patch devuelve service/kube-dns patched y la nueva lista muestra los tres puertos otra vez hacia 53, 53 y 9153. La libreta del nodo, unos segundos después, ya tiene las reglas DNAT de kube-system/kube-dns:dns hacia el puerto 53 de los Pods de CoreDNS. nslookup desde piloto contesta desde 10.96.0.10 con la IP de meteo, y el wget por nombre devuelve el nombre de una réplica. Se reparó la Service, no se cambió el directorio: el Corefile y la IP 10.96.0.10, que el kubelet escribe en el resolv.conf de cada Pod, siguen iguales. Guarde en 04-respuesta.txt las líneas PUERTO_DESTINO_RESTAURADO=, IP_DEL_DIRECTORIO= y COREFILE_INTACTO=.

</details>

```bash
./04-step.sh
./04-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 5. Cap. 9: La entrada rampa con la Gateway API e Istio, y la ruta hacia meteo (10 pts)

Objetivo: en el espacio cabina, una Gateway llamada rampa de la clase istio, con un solo listener HTTP en el puerto 80 para *.cabina.example que admite rutas solo de su mismo espacio y con una Service de tipo ClusterIP; y una HTTPRoute llamada meteo, colgada de rampa, para el nombre meteo.cabina.example y con destino la Service meteo en el puerto 80. Ambas con sus sellos en True.

La Gateway API reparte el trabajo en tres objetos con dueños distintos, como en el Capítulo 9: la GatewayClass dice quién fabrica las entradas, la Gateway es la entrada con sus carriles, y cada HTTPRoute es un letrero que un equipo cuelga en ella. Antes de probar el tráfico, lea los sellos: Programmed en la Gateway, Accepted y ResolvedRefs en la ruta. Un letrero que no enganchó o un destino que no se resuelve se ven ahí primero. La anotación de la Gateway le pide a Istio una Service ClusterIP en lugar de LoadBalancer, porque en kind no hay quien reparta IP externas; por eso todas las pruebas de este paso salen desde adentro del clúster.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es dar la ruta por buena porque el objeto existe, o llegar a meteo sin pasar por la entrada. La comprobación exige los CRD con la versión v1.6.1 anotada, istiod 1.32.0 listo, la GatewayClass istio aceptada, la Gateway rampa de esa clase con el sello Programmed=True y un solo listener HTTP en el 80 para *.cabina.example que admite rutas solo de su mismo espacio, la Service rampa-istio de tipo ClusterIP, y la HTTPRoute meteo con sus dos sellos en True. Después una sonda nueva llama a la IP de rampa-istio: con Host meteo.cabina.example tiene que contestar una réplica viva, y con un nombre que ninguna ruta reclama tiene que recibir 404, así que una entrada que lo deja pasar todo tampoco sirve.

</details>

<details>
<summary>Qué debería ver</summary>

El apply de los CRD no imprime nada y la anotación bundle-version dice v1.6.1. sha256sum -c dice istioctl.tar.gz: OK; `istioctl version` imprime `client version: 1.32.0`, y la instalación termina con Installation complete. get gatewayclass lista istio con ACCEPTED True. El apply crea la Gateway rampa y la HTTPRoute meteo; el wait deja la Gateway con condition met (Programmed), Istio crea por ella el Deployment y la Service rampa-istio, y get service la muestra de tipo ClusterIP, por la anotación, con los puertos 15021 y 80. Las condiciones de la ruta dicen Accepted=True Accepted y ResolvedRefs=True ResolvedRefs. El wget con el encabezado Host: meteo.cabina.example devuelve el nombre de una réplica de meteo; con Host: otro.cabina.example termina con server returned error: HTTP/1.1 404 Not Found, porque ninguna ruta reclama ese nombre. Guarde en 05-respuesta.txt las líneas SERVICIO_DE_LA_ENTRADA=, CLASE_DE_LA_ENTRADA= y RUTA_ACEPTADA=.

</details>

```bash
./05-step.sh
./05-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 6. Cap. 9: Una ruta que cruza de espacio, solo con el objetivo (punto sin resolver) (10 pts)

El examen no le da el comando: le da una tarea escrita como objetivo y un tiempo. Este paso es esa situación en pequeño. Todo lo que necesita lo tiene del Paso 5 y del Capítulo 9: cómo se escribe una HTTPRoute, cómo se cuelga de una Gateway, cómo se elige un nombre de anfitrión y una ruta, y qué dicen los sellos cuando algo no engancha. Lo que no tiene es una receta, ni esos datos puestos en el lugar correcto: el setup dejó la ficha, el nombre y la ruta en archivos que cambian en cada corrida, como el dato que el examen pone en el enunciado y que usted tiene que usar para alcanzar el objetivo. Tampoco hay archivo de respuesta: lo que se califica es el estado del clúster.

El objetivo está escrito como comentario al final del cmd del paso. Léalo con calma, escriba en una línea cada condición que tiene que cumplirse, y arme el estado final de a una. Si se atasca, el cmd del paso solo imprime los tres datos de la corrida: las señales están en el check_hint, que dice qué atajos están cerrados pero no cómo se hace.

<details>
<summary>Pista del verificador (check_hint)</summary>

Este es el punto sin resolver: la comprobación falla con el estado guiado de los Pasos 1 a 5 porque la ruta planilla ni siquiera existe, hasta que usted lo resuelva. Los atajos que cierra: abrir el listener de rampa a rutas de otros espacios (tiene que seguir siendo uno solo, en el 80, para *.cabina.example y con rutas solo del mismo espacio), poner la ruta en el espacio deposito, servir la ficha desde un Pod de cabina en lugar de la Service planilla de deposito (la Service tiene que ser ClusterIP con selector y su lista de extremos tiene que traer un Pod listo de deposito, así que ni una ExternalName ni una EndpointSlice hecha a mano sirven), y editar la ficha, el anfitrión o la ruta (se comparan con huellas que el setup guardó aparte). Lo decisivo es el estado final: los dos sellos de la ruta en True y una sonda nueva, con el nombre y la ruta de esta corrida, que recibe la ficha completa a través de rampa-istio. Para avanzar sin solución publicada: parta del objetivo, escriba una condición por línea y, cuando algo no funcione, lea los sellos de la ruta: el motivo que traen dice qué falta.

</details>

<details>
<summary>Qué debería ver</summary>

No se publica la secuencia de comandos de este paso: es el punto sin resolver. El estado final correcto: en el espacio deposito hay Pods que responden la ficha de esta corrida en la ruta de esta corrida, detrás de una Service planilla con puerto 80; en el espacio cabina hay una HTTPRoute planilla colgada de rampa, con el nombre de anfitrión de esta corrida y una coincidencia PathPrefix igual a la ruta de esta corrida, cuyo destino es la Service planilla del espacio deposito, con los sellos Accepted=True y ResolvedRefs=True; la Gateway rampa sigue igual que en el Paso 5; y una petición hecha desde una sonda nueva a la IP de rampa-istio, con ese nombre y esa ruta, devuelve como cuerpo la ficha completa, sin ningún otro carácter. Con lo que acaba de practicar en el Paso 5 y lo que leyó en el Capítulo 9 hay todo lo necesario.

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
  **Qué hacer:** Es el límite de inotify del anfitrión, que se comparte con los nodos porque un nodo kind es un contenedor. Suba fs.inotify.max_user_instances con sysctl (el setup imprime el valor actual), borre el clúster a medias con `kind delete cluster --name ckne-lab2 --kubeconfig ~/ckne-lab/p02/kubeconfig` y repita.

- **Síntoma (step 1):** La EndpointSlice muestra menos de tres extremos listos
  **Qué hacer:** Alguna réplica no pasó la sonda de readiness o no arrancó. Mire `kubectl -n cabina get pods -l app=meteo` y el evento de la que no está lista con describe pod; si la imagen no bajó, el problema es de red del anfitrión y no del clúster.

- **Síntoma (step 2):** El apply falla con provided port is already allocated
  **Qué hacer:** Otra Service del clúster ya tiene el nodePort 30380. Búsquela con `kubectl get svc -A | grep 30380` y bórrela o cámbiele el puerto; el laboratorio fija el 30380 para que la comprobación sepa a dónde llamar.

- **Síntoma (step 2):** conntrack no lista ninguna conexión
  **Qué hacer:** Las entradas TIME_WAIT duran poco. Repita el curl hacia el trabajador ckne-lab2-worker y corra conntrack enseguida en ese mismo nodo: la conversación queda anotada en el nodo por donde entró, no en los demás.

- **Síntoma (step 3):** El nslookup de ANTES DE LA FALLA ya falla
  **Qué hacer:** El directorio no estaba sano antes de inyectar nada. Revise que los Pods de CoreDNS estén listos (`kubectl -n kube-system get pods -l k8s-app=kube-dns`) y pregunte siempre por el nombre completo `meteo.cabina.svc.cluster.local`: el nslookup de busybox con un nombre corto recorre los dominios de búsqueda y puede terminar con código 1 aunque haya encontrado la respuesta. No corra inyectar-falla.sh hasta que el nslookup de ANTES conteste.

- **Síntoma (step 3):** inyectar-falla.sh dice que no encuentra el clúster o el kubeconfig
  **Qué hacer:** El clúster del Paso 1 no existe o se creó con otro kubeconfig. Compruebe que existe ~/ckne-lab/p02/kubeconfig y que `kind get clusters` lista ckne-lab2; si no, repita el Paso 1.

- **Síntoma (step 4):** Tras el patch, piloto sigue sin resolver durante unos segundos
  **Qué hacer:** kube-proxy reescribe las reglas cuando ve el cambio de la Service, no al instante. Mire la libreta del nodo con iptables-save hasta que las reglas DNAT de kube-system/kube-dns:dns apunten al 53, y repita el nslookup con el nombre completo.

- **Síntoma (step 4):** La comprobación dice que el Corefile cambió y usted no lo tocó
  **Qué hacer:** La huella se guarda cuando corre inyectar-falla.sh. Si corrió el guion dos veces con un Corefile editado entre medias, la huella quedó con la versión editada. Devuelva el Corefile al original de kind (está en la ConfigMap coredns de kube-system de un clúster nuevo) o rehaga el laboratorio desde el setup.

- **Síntoma (step 5):** El wait de la Gateway se agota sin Programmed
  **Qué hacer:** Mire el Pod rampa-istio en cabina: si está en ImagePullBackOff, docker.io limitó la descarga de istio/proxyv2:1.32.0 y hay que esperar o autenticarse. Si la Gateway no tiene sellos, istiod no está listo: `kubectl -n istio-system get pods`.

- **Síntoma (step 5):** El wget por la entrada falla con bad address rampa-istio.cabina
  **Qué hacer:** El directorio sigue roto: el Paso 4 no quedó reparado. Corra su comprobación antes de seguir.

- **Síntoma (step 6):** La ruta responde 500 a través de rampa
  **Qué hacer:** La ruta enganchó pero su destino no se resuelve. Lea sus sellos con `kubectl -n cabina get httproute planilla -o yaml` y busque el motivo de ResolvedRefs; el Capítulo 9 explica qué dice cada motivo.

- **Síntoma (step 6):** Mi ruta responde la ficha pero la comprobación dice que no
  **Qué hacer:** Compare lo que responde con el contenido exacto de ~/ckne-lab/p02/ficha-del-deposito.txt: un salto de línea al final no importa, pero cualquier otro carácter sí. Mire que la ruta esté en cabina, que su coincidencia sea PathPrefix con el valor exacto de ruta-del-deposito.txt, que el nombre de anfitrión sea el de anfitrion-del-deposito.txt y que la Gateway rampa no haya cambiado.

## Para ir más lejos

- Repita el Paso 3 con dig en lugar de nslookup, desde un Pod que lo traiga, y compare una consulta normal con una por TCP (dig +tcp) hacia 10.96.0.10 con la falla puesta. Explique por qué una funciona y la otra no mirando los dos puertos de la Service kube-dns, y qué cliente de su clúster real usaría TCP sin que usted se lo pida.
- Escale meteo a 5 réplicas y vuelva a contar las reglas DNAT de cabina/meteo:http en ckne-lab2-worker. Después baje a 1 y mire en la regla de KUBE-SVC cómo cambian las probabilidades del sorteo (--probability) entre extremos. Es el Capítulo 7 visto en la libreta de un nodo que usted mismo armó.

## Referencias

- Kubernetes Project, Service. ClusterIP, NodePort, named target ports and the nodePort field used in Steps 1 and 2. https://kubernetes.io/docs/concepts/services-networking/service/
- Kubernetes Project, EndpointSlices. The endpoint list with its ready condition and ports that Steps 1, 3 and 4 read. https://kubernetes.io/docs/concepts/services-networking/endpoint-slices/
- Kubernetes Project, Virtual IPs and Service Proxies. The kube-proxy modes and how it turns a Service IP into a Pod IP on each node, the basis of Steps 2 and 3. https://kubernetes.io/docs/reference/networking/virtual-ips/
- Kubernetes Project, DNS for Services and Pods. The names of the form service.namespace.svc.cluster.local and the dnsPolicy and dnsConfig fields checked in Step 4. https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/
- Kubernetes Project, Debugging DNS Resolution. The method of checking the kube-dns Service, its endpoints and the CoreDNS Pods separately, used in Steps 3 and 4. https://kubernetes.io/docs/tasks/administer-cluster/dns-debugging-resolution/
- conntrack-tools project, conntrack manual. The -L listing with -p and --dport filters used in Step 2. https://conntrack-tools.netfilter.org/manual.html
- Gateway API project, Getting started and the v1.6.1 release. The standard-channel install file and the Gateway and HTTPRoute objects of Steps 5 and 6. https://gateway-api.sigs.k8s.io/guides/getting-started/ and https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.6.1
- Istio Project, Gateway API task and the 1.32.0 release. The gatewayClassName istio and the Deployment and Service each Gateway provisions, named <Gateway name>-<GatewayClass name>, used in Step 5. https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/ and https://github.com/istio/istio/releases/tag/1.32.0
- Istio Project, Getting Started. The networking.istio.io/service-type=ClusterIP annotation on a Gateway, used in Step 5 because kind hands out no LoadBalancer addresses. https://istio.io/latest/docs/setup/additional-setup/getting-started/
- Calico Project, Install Calico on a kind cluster. The kind configuration with disableDefaultCNI and podSubnet, and the manifest URL pinned to v3.33.0, used in Step 1. https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
