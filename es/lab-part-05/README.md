# Parte V - Laboratorio: quién entra a una zona, qué viaja cifrado entre nodos, un candado que emite cert-manager y la identidad de cada Pod

- Tiempo: 60 min
- Puntos: 70

## Objetivo

Este es un laboratorio Exam-Style: cada paso le dice solamente el objetivo y el entregable, y la secuencia de comandos del paso vive en el campo cmd para que la revele después de haber intentado por su cuenta. La excepción es el Paso 7: ese solo declara el objetivo, no hay comando publicado en ningún lado del repositorio, y su comprobación depende de una ficha distinta en cada corrida. Qué se construye, en cuatro clústeres de kind independientes: el Paso 1 monta `ckne-lab5-red` (Calico 3.33.1) y deja que solo los operarios de la `maestranza` lleguen a las `existencias` del depósito (Capítulo 13). El Paso 2 pone encima la capa del administrador: una ClusterNetworkPolicy del nivel Admin que cierra el paso a un espacio aunque una NetworkPolicy lo deje abierto (Capítulo 13). El Paso 3 monta `ckne-lab5-cifra` (Cilium 1.20.5), activa el cifrado transparente con WireGuard y lo prueba con capturas en el nodo, no con lo que dice el agente (Capítulo 14). El Paso 4 monta `ckne-lab5-sello` (Istio 1.32.0, Gateway API 1.6.1, cert-manager v1.21.3) y da un listener HTTPS cuyo certificado emite cert-manager desde una anotación del Gateway (Capítulo 15). El Paso 5 corre `inyectar-falla.sh`, un guion que rompe a ciegas otro listener de ese Gateway: su contenido va codificado a propósito, como una venda de cortesía y no como un secreto real; hay que diagnosticar en el orden del Capítulo 15 y repararlo (Capítulo 15). El Paso 6 monta `ckne-lab5-id` (SPIRE 1.16.0 por el chart 0.31.0, Istio 1.32.0) y lee la identidad de un servidor, su registro y el pase de un Pod (Capítulo 16). El Paso 7 es el examen en miniatura: un servicio de esa malla que solo una identidad puede leer, sin comando publicado (Capítulo 16).

## Prerrequisitos

- Una máquina Linux con kind, kubectl, docker, helm, jq, curl, tar, sha256sum, base64, od y openssl en el PATH, y con al menos 14 GB de RAM libres: el laboratorio levanta nueve nodos de kind en cuatro clústeres (`ckne-lab5-red`, `ckne-lab5-cifra`, `ckne-lab5-sello` y `ckne-lab5-id`) y los elimina todos en el teardown.
- AISLAMIENTO. Los clústeres de este laboratorio NUNCA tocan su kubeconfig de siempre: se crean con --kubeconfig ~/ckne-lab/p04/kubeconfig desde el primer comando, y todos los kubectl, helm e istioctl del laboratorio pasan ese archivo y un contexto explícito. Helm se usa con --repo, así que tampoco se agregan repositorios a su configuración. Si ya tiene otros clústeres de kind, este laboratorio no los ve, no los modifica y no los borra. El setup imprime kind get clusters antes de empezar para que lo compruebe.
- El Paso 3 cifra con WireGuard, y los nodos de kind comparten el kernel del anfitrión: el módulo tiene que estar cargado ahí antes de empezar (sudo modprobe wireguard). El setup lo comprueba y se detiene con un mensaje si falta. Es lo único del laboratorio que necesita permisos de administrador del anfitrión.
- Acceso a internet durante todo el laboratorio: kind descarga la imagen del nodo; el Paso 1 baja el manifiesto de Calico desde raw.githubusercontent.com; Helm baja Cilium de helm.cilium.io, cert-manager de quay.io y SPIRE de spiffe.github.io; el Paso 4 baja los CRD de la Gateway API y el binario istioctl desde github.com; los Pods bajan nginx, curl, netshoot y busybox fijados por digest o por versión. El tiempo de 60 minutos cuenta con las imágenes ya descargadas; en la primera corrida suma la descarga. La ruta guiada de los Pasos 1 a 6 tomó 9 minutos de máquina (562 s) en la corrida de verificación; el resto es lectura, los entregables y el Paso 7, que no se midió con una persona. Los 14 GB de RAM son una estimación, no una medición.
- Un clúster nuevo por cada uno de los cuatro temas, con nombres que no usan los capítulos: ni los espacios, ni los Pods, ni los Gateways de estas páginas se repiten aquí. Lo que sí se repite son las herramientas y las versiones: Calico 3.33.1, Cilium 1.20.5, cert-manager v1.21.3, Istio 1.32.0 y SPIRE 1.16.0.

## Pasos

El `0N-step.sh` está para que no se quede atascado: lea el paso, intente primero por su cuenta y corra el script cuando quiera comparar. Escribe también el archivo de respuesta que el paso pide, leyendo los valores del clúster vivo.

### 1. Cap. 13: Solo los operarios de la `maestranza` llegan a las `existencias` (10 pts)

Objetivo: en el clúster `ckne-lab5-red` (un plano de control y un trabajador, Calico 3.33.1 y sin kindnet), tres espacios con la etiqueta zona igual a su nombre: `deposito`, con la Service `existencias` (nginx, puerto 80); `maestranza`, con los Pods operario (rol=operario) y novato (rol=novato); y afuera, con otro Pod operario (rol=operario). Una NetworkPolicy llamada `solo-operarios` en `deposito` para que `existencias` reciba solo de los Pods rol=operario de los espacios `zona=maestranza`. Entregable: 01-respuesta.txt con PASA (quién recibe 200) y SIN_RESPUESTA (quién no, separados por coma y en orden alfabético).

El Capítulo 13 dejó un método: cada regla se prueba desde un Pod que debe pasar y desde uno que no. Esta matriz tiene dos Pods que no deben pasar por razones distintas: uno porque tiene el rol equivocado en el espacio correcto, el otro porque tiene el rol correcto en el espacio equivocado. Una regla que deje pasar a cualquiera de los dos está mal escrita, aunque el que debía pasar pase.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es quitar a los Pods que molestan o cambiarles la etiqueta. La comprobación lo cierra: exige el clúster de dos nodos Ready en v1.37.0 con Calico v3.33.1 listo; los tres espacios con su etiqueta zona igual a su nombre; la Service `existencias` en el depósito con su réplica lista; los tres Pods en Running con sus etiquetas rol originales; al menos una NetworkPolicy en el depósito (el nombre `solo-operarios` del objetivo no se comprueba). Después pide en vivo desde cada Pod: `maestranza/operario` tiene que recibir 200 y los otros dos no. Por último compara 01-respuesta.txt con lo que la matriz dice.

</details>

<details>
<summary>Qué debería ver</summary>

kind create termina con Set kubectl context to `kind-ckne-lab5-red`, el daemonset calico-node de Calico v3.33.1 termina con successfully rolled out y los dos nodos quedan en condition met. Antes de la política, la matriz muestra 200 en las tres filas: todos pasan. Después de aplicar `solo-operarios`, pasa `maestranza/operario` con 200 y las otras dos filas, `maestranza/novato` y afuera/operario, quedan en 000 exit 28 (la petición se agota sin respuesta, no se rechaza). El truco está en la forma de la política: un solo elemento de from con la etiqueta del espacio Y la del Pod juntas. Si fueran dos elementos, se leería como O y dejaría pasar a cualquier Pod de la `maestranza` y a cualquier operario de cualquier espacio. 01-respuesta.txt queda con `PASA=maestranza/operario` y `SIN_RESPUESTA=afuera/operario,maestranza/novato`.

</details>

```bash
./01-step.sh
./01-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 2. Cap. 13: La capa del administrador cierra lo que una NetworkPolicy dejó abierto (10 pts)

Objetivo: en `ckne-lab5-red`, el espacio `verbena` (etiqueta `zona=verbena`) con la Service `mostrario` (nginx, puerto 80) y una NetworkPolicy `abre-a-todos` que deja entrar todo el tráfico. Encima, una ClusterNetworkPolicy llamada `cierre-de-afuera`, del nivel Admin y prioridad 10, cuyo sujeto sea el espacio `zona=verbena` y que deniegue el ingreso desde los espacios zona=afuera. Los Pods de la `maestranza` tienen que seguir llegando. Entregable: 02-respuesta.txt.

El administrador del clúster no puede depender de que cada equipo cierre bien su espacio. El Capítulo 13 mostró dónde se evalúa su capa respecto de las NetworkPolicy de los equipos; este paso lo comprueba con una NetworkPolicy que, a propósito, lo deja todo abierto.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es borrar o reescribir la NetworkPolicy `abre-a-todos` para cerrar a afuera. La comprobación lo cierra: exige que `abre-a-todos` siga con su spec original y que sea la única NetworkPolicy de `verbena`; que exista la ClusterNetworkPolicy `cierre-de-afuera` con tier Admin, un solo ingreso con acción Deny, prioridad 10, y el sujeto y el origen por etiqueta de zona; y las dos lecturas en vivo (`maestranza` pasa, afuera no).

</details>

<details>
<summary>Qué debería ver</summary>

Se crea el espacio `verbena` con su etiqueta, la Service `mostrario` con una réplica y la NetworkPolicy `abre-a-todos`, que permite todo el ingreso. Antes de la capa del administrador, las dos filas dan 200. Después de aplicar `cierre-de-afuera`, `maestranza/operario` sigue en 200 y afuera/operario queda en 000 exit 28, aunque `abre-a-todos` siga ahí: el nivel Admin se evalúa antes que cualquier NetworkPolicy. 02-respuesta.txt queda con NIVEL=Admin, ACCION=Deny y NETWORKPOLICY_INTACTA=si.

</details>

```bash
./02-step.sh
./02-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 3. Cap. 14: Cifrar entre nodos con WireGuard, comprobado con una captura en el nodo (10 pts)

Objetivo: en `ckne-lab5-cifra` (un plano de control y dos trabajadores, Cilium 1.20.5 con el kube-proxy de siempre), el espacio `faro` con el Pod origen (netshoot, en el primer trabajador), el Pod destino (nginx, en el segundo) y el Pod `puente` (nginx con hostNetwork, también en el segundo). Cifrado transparente entre nodos con WireGuard, y una prueba que no dependa de lo que informe el agente: una ficha nueva en una petición de origen a destino, buscada en una captura de eth0 del nodo de origen. Entregable: 03-respuesta.txt.

La forma de probar que dejó el Capítulo 14 sirve aquí: meter en la petición un texto que no esté en ninguna otra parte y buscarlo en una captura del nodo. La ficha de este laboratorio es ese texto (el pase secreto del capítulo, con otro nombre). Un agente puede informar Wireguard y aun así haber tráfico que cruza legible por la red de los nodos: por eso hay un tercer Pod, `puente`, que está en la red del nodo y no en la de los Pods, y por eso se mide también hacia él.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es fiarse de lo que dice un agente, o poner a los dos Pods en el mismo nodo. La comprobación lo cierra: exige el clúster de tres nodos Ready con Cilium v1.20.5 listo en los tres; origen en `ckne-lab5-cifra-worker` y destino en `ckne-lab5-cifra-worker2`, sin hostNetwork, y `puente` con hostNetwork; los tres agentes diciendo Wireguard. Después hace sus propias capturas con una ficha nueva: de origen a destino la ficha no puede quedar legible en eth0 y tiene que haber paquetes UDP 51871, y la lectura hacia `puente` se compara con la que usted escribió. Los números de 03-respuesta.txt tienen que ser los que esa captura mide.

</details>

<details>
<summary>Qué debería ver</summary>

kind create termina con Set kubectl context to `kind-ckne-lab5-cifra`, Cilium v1.20.5 termina con successfully rolled out y los tres nodos quedan en condition met. Los Pods origen (en `ckne-lab5-cifra-worker`), destino (en `ckne-lab5-cifra-worker2`) y `puente` (hostNetwork, en `ckne-lab5-cifra-worker2`) quedan Running. Antes de cifrar, la captura de origen a destino da ficha-legible 1 y udp-8472 con paquetes: viaja encapsulado en VXLAN pero sin cifrar. Tras el helm upgrade y el reinicio de los agentes, los tres dicen Encryption: Wireguard; la captura de origen a destino da ficha-legible 0 y udp-51871 con paquetes. La captura hacia `puente` da ficha-legible 1: ese tráfico va por la red de los nodos, no por la de los Pods, y los agentes imprimen NodeEncryption: Disabled. 03-respuesta.txt queda con AGENTES_CON_WIREGUARD=3, FICHA_LEGIBLE_ENTRE_PODS=0, UDP_51871_ENTRE_PODS=si y FICHA_LEGIBLE_HACIA_EL_PUENTE=1.

</details>

```bash
./03-step.sh
./03-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 4. Cap. 15: Un listener HTTPS cuyo certificado emite cert-manager, leído desde un cliente que tiene la raíz (10 pts)

Objetivo: en `ckne-lab5-sello` (un plano de control y un trabajador), Istio 1.32.0 con perfil minimal, la Gateway API v1.6.1 y cert-manager v1.21.3 con la Gateway API activa; una raíz propia (`raiz-lab`) y un ClusterIssuer `casa-emisora` que firma con ella; la aplicación `letrero` en el espacio `ribera`, el Gateway `entrada-lab` en el espacio `dique` y un cliente `cliente-tls` con la raíz. Después, en `entrada-lab`, un listener HTTPS en el 443 para `letrero.lab.example` cuyo certificado pida cert-manager por la anotación del Gateway a `casa-emisora`, con vigencia de 2 horas y renovación a 1 hora. Entregable: 04-respuesta.txt.

El Capítulo 15 dio la secuencia para mirar un listener: sus condiciones y el mensaje, después el Certificate y sus eventos, y al final la cadena vista desde un cliente que tiene la raíz. Este paso la usa de principio a fin con un listener que sí funciona, para que el siguiente la use con uno que no. Un certificado emitido a mano y puesto en un Secret abre el candado igual, pero no es lo que se pide: cert-manager es quien lo emite y lo renueva.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es crear el certificado a mano y ponerlo en un Secret. La comprobación lo cierra: exige Istio 1.32.0, cert-manager v1.21.3 y los CRD v1.6.1; la raíz y el emisor Ready; en el Gateway `entrada-lab` las tres anotaciones de cert-manager con el emisor `casa-emisora`, vigencia 2h y renovación a 1h, y un solo listener HTTPS de puerto 443 con el nombre `letrero.lab.example`, tls en modo `Terminate` y la referencia al Secret `letrero-tls`; las condiciones de sus dos listeners en True; y el Certificate `letrero-tls` con el Gateway como dueño, el emisor, el nombre, la vigencia y la renovación pedidos y Ready. Después hace su propia lectura desde el cliente con la raíz copiada en ese momento: la cadena tiene que verificar con el nombre y la página tiene que llegar. La serie de 04-respuesta.txt es la que el puerto 443 sirve ahora.

</details>

<details>
<summary>Qué debería ver</summary>

kind create termina con Set kubectl context to `kind-ckne-lab5-sello`; los CRD de la Gateway API v1.6.1 se aplican; la huella de istioctl imprime OK e Istio termina con Installation complete; el helm install de cert-manager v1.21.3 con --wait termina sin error. La raíz `raiz-lab` y el emisor `casa-emisora` quedan Ready. Antes del listener HTTPS, la petición al puerto 80 devuelve la página `letrero: salida 7 puntual`. Después de aplicar el Gateway con la anotación, el Certificate `letrero-tls` aparece, queda Ready y las condiciones de los dos listeners son True (Accepted, Programmed, ResolvedRefs). El certificado que sirve el puerto 443 trae el SAN `letrero.lab.example` y el emisor CN=Autoridad del puerto, y el curl con la raíz imprime la misma página. 04-respuesta.txt queda con `CERTIFICADO=letrero-tls`, `EMISOR=casa-emisora`, REVISION=1 y la serie del certificado servido.

</details>

```bash
./04-step.sh
./04-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 5. Cap. 15: Otro listener que no cifra, diagnosticado en el orden del capítulo (10 pts)

Objetivo: en `ckne-lab5-sello`, un Gateway llamado `embarcadero` en el espacio `dique`, con un listener https para `embarcadero.lab.example` y una ruta en `ribera` hacia la aplicación `letrero`, sirve el certificado de este laboratorio y el cliente `cliente-tls` recibe la página con la raíz en la mano. Hoy no cifra: `inyectar-falla.sh` lo deja roto. Ubique la falla leyendo en el orden del Capítulo 15, repárela sin borrar ni recrear el Gateway y deje el diagnóstico escrito. Entregables: 05-diagnostico.txt, con una sección por lectura (1 el listener y su mensaje, 2 el Certificate y sus eventos, 3 la cadena vista desde el cliente) y 05-respuesta.txt.

Un listener que no cifra no siempre devuelve un error que se lea de una vez: el cliente solo ve que no conecta. Las lecturas del Paso 4 sirven aquí con otros nombres (el Gateway es `embarcadero` y el host `embarcadero.lab.example`). El orden importa porque cada lectura acota la siguiente.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es borrar el Gateway y crear otro, o repararlo sin haber leído nada. La comprobación lo cierra: exige que 05-diagnostico.txt sea más nuevo que la falla, traiga las tres secciones, la lectura del listener https con su condición en False y el nombre exacto que usted halló fuera de lugar; que el Gateway `embarcadero` sea el mismo objeto que se rompió; que su listener https y su ruta sigan como estaban; que sus condiciones estén en True y que el Certificate `embarcadero-tls` lo haya creado cert-manager (el Gateway es su dueño), esté Ready y quede con la configuración del Paso 4; y que desde el cliente con la raíz la cadena verifique con el nombre y la página llegue. Las cuatro líneas de 05-respuesta.txt tienen que coincidir con lo que la falla dejó.

</details>

<details>
<summary>Qué debería ver</summary>

`inyectar-falla.sh` imprime falla inyectada. EL SINTOMA: el cliente pide `embarcadero.lab.example` por el 443 y recibe curl: (7) Failed to connect: ese listener no está sirviendo. El diagnóstico, guardado en 05-diagnostico.txt, lee en el orden del Capítulo 15. 1: el listener https está Accepted=True pero Programmed=False (Invalid) y ResolvedRefs=False (InvalidCertificateRef), con el mensaje secret `dique/embarcadero-tls` not found. 2: el Certificate `embarcadero-tls` existe pero no está Ready; su CertificateRequest apunta al emisor `casa-emisora-nueva` y los eventos dicen IssuerNotFound con ese nombre. 3: desde el cliente, openssl s_client recibe Connection refused. Una cuarta lectura que añade el cmd, fuera de las tres secciones que exige la comprobación: la anotación cert-manager.io/cluster-issuer del Gateway dice `casa-emisora-nueva`, y los emisores que existen son `casa-emisora` y `semilla-lab`. La reparación es poner en la anotación el emisor que existe: cert-manager vuelve a pedir el certificado, el listener pasa a Programmed y ResolvedRefs en True y el cliente recibe la página. 05-respuesta.txt queda con el listener, la condición, el emisor que no existía y el correcto.

</details>

```bash
./05-step.sh
./05-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 6. Cap. 16: La identidad de un servidor y el pase de un Pod, leídos en vivo (10 pts)

Objetivo: en `ckne-lab5-id` (un plano de control y un trabajador), SPIRE con el dominio de confianza `lab.test` y el nombre de clúster `ckne-lab5-id`, e Istio 1.32.0 (el istioctl que bajó el Paso 4) con ese mismo dominio y la plantilla spire; el espacio `cubierta` con inyección, las ServiceAccount `capitan`, `invitado` y `bascula`; el Deployment `bascula` (nginx, con la plantilla sidecar y spire) y su Service; y el Pod `portador` (ServiceAccount `capitan`) con un pase de audiencia `bascula` y 900 segundos. Entregable: 06-respuesta.txt, con lo que lea del documento del sidecar, del pase y del registro de SPIRE.

Para la parte de identidad el Capítulo 16 pidió dos comprobaciones: abrir el documento antes de escribir una regla y, cuando una regla no parezca actuar, repetir la petición con el tiempo a la vista. Este paso es la primera: deja leídos el documento, el pase y el registro. El pase (el pasaporte del capítulo) es una cosa y el documento del sidecar es otra: el primero lo firma Kubernetes para hablar con una API, el segundo lo firma SPIRE para hablar entre servicios.

<details>
<summary>Pista del verificador (check_hint)</summary>

El atajo de este paso es escribir en 06-respuesta.txt lo que el capítulo mostró. La comprobación lo cierra: exige SPIRE (el servidor listo, un agente, el dominio de confianza `lab.test`) e Istio 1.32.0 con ese mismo dominio; el espacio `cubierta` con inyección y sus tres ServiceAccount; la `bascula` con la plantilla sidecar,spire; y lee en vivo el documento del sidecar (el URI del dominio de confianza y O = SPIRE en el subject del documento), la entrada de SPIRE con el uid del Pod actual de la `bascula` y el pase de `portador` (audiencia `bascula`, 900 s, ServiceAccount `capitan`). Las cinco líneas de 06-respuesta.txt tienen que coincidir con lo que esas lecturas dan ahora, incluido el número de entradas.

</details>

<details>
<summary>Qué debería ver</summary>

kind create termina con Set kubectl context to `kind-ckne-lab5-id`; el chart de SPIRE deja spire-server-0 2/2, un spire-agent, el driver CSI y el proveedor OIDC; Istio termina con Installation complete. En `cubierta`, la `bascula` queda 2/2 y `portador` 2/2. El documento del sidecar de la `bascula` trae subject=C = US, O = SPIRE y el URI `spiffe://lab.test/ns/cubierta/sa/bascula`; la línea issuer sale con el nombre por omisión de la CA de SPIRE (CN = example.org), y EMISOR_DE_LA_IDENTIDAD lleva la O del subject. El pase de `portador` trae sub `system:serviceaccount:cubierta:capitan`, aud `bascula` y vida 900. SPIRE registra una entrada por Pod, `/ns/cubierta/sa/bascula` y `/ns/cubierta/sa/capitan`, cada una con su selector k8s:pod-uid. 06-respuesta.txt queda con el URI de la `bascula`, SPIRE, `bascula`, 900 y 2 entradas.

</details>

```bash
./06-step.sh
./06-check.sh
```

El verificador imprime `ok` y sale con 0 cuando el paso quedó bien, y sale con 1 cuando no. No le cree su palabra: vuelve a consultar el clúster en vivo.

### 7. Cap. 16: Un servicio que solo una identidad puede leer, solo con el objetivo (punto sin resolver) (10 pts)

El examen no le da el comando: le da una tarea escrita como objetivo. Este paso es esa situación en pequeño. Todo lo que necesita lo tiene del Paso 6 y del Capítulo 16: cómo se hace entrar un Pod en la malla con su identidad, qué dice el documento y cómo se mide una regla cuando tarda en actuar. Lo que no tiene es una receta: el setup dejó la ficha en un archivo que cambia en cada corrida, como el dato que el examen pone en el enunciado. Tampoco hay archivo de respuesta: lo que se califica es el estado del clúster.

El objetivo está escrito como comentario al final del cmd del paso. Léalo con calma, escriba en una línea cada condición que tiene que cumplirse, y arme el estado final de a una. Cuando algo no funcione, lea el estado de cada objeto y repita la petición mirando el tiempo.

<details>
<summary>Pista del verificador (check_hint)</summary>

Este es el punto sin resolver: la comprobación falla con el estado guiado de los Pasos 1 a 6 porque `bahia` ni siquiera existe, hasta que usted lo resuelva. Los atajos que cierra: editar la ficha (se compara con una huella que el setup guardó aparte) y dejar a los Pods sin la identidad de SPIRE. Las sondas son nuevas y cada una trae una ServiceAccount distinta. Lo decisivo es que una sonda nueva con `jefe-de-bahia` reciba la ficha completa dos veces y que las otras dos reciban 403, no un error de conexión.

</details>

<details>
<summary>Qué debería ver</summary>

No se publica la secuencia de comandos de este paso: es el punto sin resolver. El estado final correcto: en `ckne-lab5-id` existe el espacio `bahia` con inyección, la ServiceAccount `jefe-de-bahia` y una Service `cofre` de tipo ClusterIP con selector y puerto 80, cuyos Pods son de la malla con su identidad de SPIRE y responden la ficha de esta corrida en la raíz; y solo la identidad de `jefe-de-bahia` recibe la ficha: cualquier otra, sea del mismo espacio o de otro, recibe 403. La comprobación crea tres sondas nuevas (la de `jefe-de-bahia`, una de otra ServiceAccount del mismo espacio y una de un espacio ajeno) y repite la petición con el tiempo a la vista hasta que la regla actúa.

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

- **Síntoma (step 1):** El kind create falla con too many open files
  **Qué hacer:** Es el límite de inotify del anfitrión, compartido por todos los nodos. Suba fs.inotify.max_user_instances con sysctl (el setup imprime el valor actual), borre el clúster a medias con kind delete cluster --name `ckne-lab5-red` --kubeconfig ~/ckne-lab/p04/kubeconfig y repita.

- **Síntoma (step 1):** Los tres Pods devuelven 000 desde antes de aplicar la política
  **Qué hacer:** Calico o CoreDNS todavía no terminaron de arrancar. Espere a que calico-node y coredns estén listos con kubectl -n kube-system get pods y repita la matriz.

- **Síntoma (step 2):** kubectl no reconoce el tipo ClusterNetworkPolicy
  **Qué hacer:** El CRD lo instala Calico v3.33.1. Compruebe con kubectl get crd | grep clusternetworkpolicies que existe, y que el apiVersion del manifiesto sea policy.networking.k8s.io/v1alpha2.

- **Síntoma (step 2):** Aplicó la política y afuera sigue recibiendo 200
  **Qué hacer:** Las reglas tardan unos segundos en llegar a los nodos: espere cinco segundos y repita la matriz. Si sigue, lea el nivel y la prioridad con kubectl get clusternetworkpolicy y compare el nivel con el que usó el Capítulo 13.

- **Síntoma (step 3):** Los agentes dicen Encryption: Disabled después del helm upgrade
  **Qué hacer:** Un agente lee su configuración al arrancar. Compruebe con helm get values cilium -n kube-system que el cifrado quedó pedido y reinicie el daemonset cilium; espere a que termine el rollout antes de volver a mirar.

- **Síntoma (step 3):** La captura imprime ficha-legible 0 y también udp-51871 0 y udp-8472 0
  **Qué hacer:** No capturó nada: la petición no salió por esa interfaz. Compruebe que origen y destino están en nodos distintos con kubectl -n `faro` get pods -o wide y que pidió el nodo de origen, no el de destino.

- **Síntoma (step 4):** El Certificate `letrero-tls` no aparece
  **Qué hacer:** cert-manager solo mira los Gateways si se instaló con la Gateway API activa. Compruebe con helm get values cert-manager -n cert-manager que gatewayAPI.enabled sea true y que el Gateway lleve las anotaciones en metadata.annotations, no en spec.

- **Síntoma (step 4):** La comprobación del Paso 4 falla en REVISION o SERIE_SERVIDA sin que usted haya cambiado nada
  **Qué hacer:** Una reemisión del certificado cambia la revisión y la serie que sirve el 443 (la corrida de verificación lo vio al cambiar la vigencia). Vuelva a leer ambas y reescriba 04-respuesta.txt.

- **Síntoma (step 4):** curl dice unable to get local issuer certificate
  **Qué hacer:** El cliente no tiene la raíz de esta corrida. Cópiela del Secret `raiz-lab` (clave ca.crt) a `/raiz.crt` en `cliente-tls` y pida con `--cacert /raiz.crt`; el nombre del certificado y el de la petición tienen que ser el mismo.

- **Síntoma (step 5):** El cliente dice Connection refused en el 443
  **Qué hacer:** El proxy no abre el puerto de ese listener. Lea primero las condiciones del listener y el mensaje de la condición que está en False, antes de tocar ningún objeto.

- **Síntoma (step 5):** Después de reparar, la condición del listener sigue en False
  **Qué hacer:** cert-manager reintenta con una espera creciente. Espere un minuto y mire de nuevo el Certificate y sus eventos con kubectl -n `dique` get certificate y kubectl -n `dique` events; el evento más reciente dice dónde está.

- **Síntoma (step 6):** Los Pods de `cubierta` se quedan en 1/2 o en Init
  **Qué hacer:** El sidecar espera el socket de SPIRE. Compruebe que el chart terminó (kubectl -n spire-server get pods, con el driver CSI en 2/2) y que la plantilla spire quedó en la configuración de Istio; después borre el Pod para que se cree de nuevo.

- **Síntoma (step 6):** istioctl no se encuentra
  **Qué hacer:** Use el que bajó el Paso 4: ./bin/istioctl desde ~/ckne-lab/p04, con --kubeconfig y --context explícitos. Este paso no lo descarga otra vez.

- **Síntoma (step 7):** El Pod de `cofre` se queda en 1/2
  **Qué hacer:** Mire los eventos del Pod con kubectl -n `bahia` describe pod y compare lo que declaró con lo que hizo con los Pods de `cubierta` en el Paso 6.

- **Síntoma (step 7):** Mi Service responde la ficha pero la comprobación dice que no
  **Qué hacer:** Compare lo que responde con el contenido de `~/ckne-lab/p04/ficha-del-cofre.txt`: un salto de línea al final no importa, pero cualquier otro carácter sí. Pida con una sonda propia desde cada identidad y mire el código además del cuerpo.

## Para ir más lejos

- En el Paso 1, cambie la política para que sean dos elementos en from en lugar de uno y repita la matriz. Cuente quién pasa ahora, y explique con las etiquetas de los tres Pods por qué cambió.
- En el Paso 3, active también el cifrado de los nodos con encryption.nodeEncryption y repita la captura hacia `puente` desde cada nodo. Anote qué lee cada captura y busque en la documentación de Cilium por qué. Esto puede cambiar lo que mide la comprobación del Paso 3: hágalo después de comprobar el paso.
- En el Paso 7, cree un segundo Pod con la ServiceAccount `jefe-de-bahia` pero en otro espacio y mida si recibe la ficha. Hágalo después de comprobar el Paso 7. Explique con lo que dice el documento de identidad por qué sí o por qué no.

## Referencias

- Kubernetes, Network Policies. The AND and OR of from selectors and the isolation model used in Steps 1 and 2. https://kubernetes.io/docs/concepts/services-networking/network-policies/
- Calico, tiered policy and the kind installation guide (v3.33). The Calico manifest on kind and the tiers behind the Admin layer used in Steps 1 and 2. https://docs.tigera.io/calico/latest/network-policy/policy-tiers/tiered-policy and https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind
- Kubernetes SIG Network, network-policy-api. The ClusterNetworkPolicy resource with its Admin and Baseline tiers, used in Step 2. https://network-policy-api.sigs.k8s.io/
- Cilium Project, WireGuard transparent encryption (stable). encryption.type wireguard, cilium-dbg encrypt status and UDP port 51871, used in Step 3. https://docs.cilium.io/en/stable/security/network/encryption-wireguard/
- Cilium Project, Installation using kind. The kind configuration with the default CNI disabled, used in Step 3. https://docs.cilium.io/en/stable/installation/kind/
- cert-manager, Securing Gateway resources. The cert-manager.io/cluster-issuer, duration and renew-before annotations on a Gateway, used in Steps 4 and 5. https://cert-manager.io/docs/usage/gateway/
- cert-manager, CA issuer and self-signed issuer. The root and the issuer built in Step 4. https://cert-manager.io/docs/configuration/ca/ and https://cert-manager.io/docs/configuration/selfsigned/
- Gateway API, TLS guide. The HTTPS listener, tls.mode Terminate and certificateRefs used in Steps 4 and 5. https://gateway-api.sigs.k8s.io/guides/user-guides/tls/
- OpenSSL, openssl-s_client (3.5). The chain read from a client that holds the root, used in Steps 4 and 5. https://docs.openssl.org/3.5/man1/openssl-s_client/
- Istio Project, SPIRE integration. The spire sidecar template and the SPIFFE CSI socket used in Steps 6 and 7. https://istio.io/latest/docs/ops/integrations/spire/
- SPIFFE helm-charts-hardened, spire 0.31.0 release. The chart and the spire-crds chart used in Step 6. https://github.com/spiffe/helm-charts-hardened/releases/tag/spire-0.31.0
- Istio Project, AuthorizationPolicy reference. Authorization rules in the mesh, used in Step 7. https://istio.io/latest/docs/reference/config/security/authorization-policy/

---

_Hecho con ❤️ por Luis Felipe Ariza Vesga._
