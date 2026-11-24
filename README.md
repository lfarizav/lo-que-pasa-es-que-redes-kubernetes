# Lo que pasa es que la red de Kubernetes

**Los laboratorios del libro.** · **The book's labs.**

Si usted llegó aquí desde el libro, está en el lugar correcto. Aquí están los laboratorios del
libro, uno por cada parte, listos para clonar y ejecutar.

If you got here from the book, you are in the right place. These are the book's labs, one per
part, ready to clone and run.

---

## Español

### El libro

**Lo que pasa es que la red de Kubernetes.** *Guía completa de redes en Kubernetes en lenguaje sencillo.*
Dieciocho capítulos en seis partes, con un laboratorio por parte. Cubre los dominios de la
certificación **CKNE** (Certified Kubernetes Network Engineer): infraestructura central y CNI,
redes de servicios y DNS, gestión avanzada del tráfico, seguridad y políticas de red, y
observabilidad. Sigue la apuesta del resto de la serie: si usted entiende el mecanismo, no
tiene que memorizar la respuesta. La analogía es un aeropuerto, con sus pistas, sus puertas
numeradas, su directorio de vuelos, su control de seguridad y su torre de control.

Material de estudio independiente. No está afiliado a la Linux Foundation ni a la Cloud
Native Computing Foundation, ni cuenta con su respaldo. Los laboratorios imitan el formato
de la certificación (tareas calificadas por el estado final del clúster) y nunca su contenido.

### Qué son estos laboratorios

Cada laboratorio es una práctica de 50 a 60 minutos de trabajo real contra un clúster de
verdad (kind, dentro de Docker). Cada paso le da un objetivo y un entregable, y se califica
por el **estado final del clúster**, no por lo que usted escribió ni por el camino que tomó.
El último paso de cada laboratorio trae solo el objetivo, sin solución publicada. Cada
laboratorio se publica aquí solo después de ejecutarlo completo en kind, de principio a fin.

### Cuándo hacer cada laboratorio

Hay un laboratorio por cada parte del libro, y cada uno usa **todo** lo de esa parte, no
solo el último capítulo. El momento de hacerlo es cuando usted termina la parte completa.

| Termine de leer | Y entonces corra | Tiempo | Puntos |
|---|---|---|---|
| Capítulo 2, *El reglamento del aeropuerto y la pista de práctica* (cierra la Parte I) | `es/lab-part-01` | 50 min | 50 |
| Capítulo 5, *La lupa del inspector de equipajes* (cierra la Parte II) | `es/lab-part-02` | 60 min | 60 |
| Capítulo 9, *La puerta principal de la terminal por la Gateway API* (cierra la Parte III) | `es/lab-part-03` | 60 min | 60 |
| Capítulo 12, *Dos aeropuertos que se hablan* (cierra la Parte IV) | `es/lab-part-04` | 60 min | 70 |
| Capítulo 16, *El pasaporte de cada Pod* (cierra la Parte V) | `es/lab-part-05` | 60 min | 70 |
| Capítulo 18, *Seguir la maleta y leer la bitácora de vuelo* (cierra la Parte VI) | `es/lab-part-06` | 60 min | 70 |

### Antes de empezar

Necesita una máquina Linux con estas herramientas instaladas y funcionando:

| Herramienta | Para qué | Versión con la que se probó |
|---|---|---|
| `docker` | correr los nodos de los clústeres | 29.10.0 |
| `kind` | crear los clústeres de práctica | v0.33.0 |
| `kubectl` | hablarle al clúster | v1.37.0 |
| `helm` | instalar componentes desde la Parte IV | v4.3.0 |
| `jq` | leer las respuestas del clúster en los verificadores | 1.7 |
| `curl` | descargar y probar endpoints desde la Parte II | 8.5.0 |
| `openssl` | revisar certificados en la Parte V | 3.0.13 |
| `tar`, `sha256sum`, `base64`, `od` | desempacar descargas y comparar huellas | las de su distribución |

Versiones cercanas también sirven. Los clústeres se crean con la imagen `kindest/node:v1.37.0`
fijada por digest, y los laboratorios necesitan internet al montarse. La memoria libre que
pide cada uno va de 4 GB (Partes I y II) a 12 GB (Parte IV) y 14 GB (Parte V), porque esas
dos levantan varios clústeres a la vez. Cada `README.md` dice qué más usa ese laboratorio.

### Empiece aquí

```bash
git clone https://github.com/lfarizav/lo-que-pasa-es-que-redes-kubernetes.git
cd lo-que-pasa-es-que-redes-kubernetes/es/lab-part-01
cat README.md
```

El repositorio tiene dos carpetas: `es/` (español) y `en/` (inglés). Los scripts son los
mismos; cambia el idioma del `README.md` de cada laboratorio. Cada laboratorio se corre
siempre igual: montaje, cada paso con su verificador, y desmontaje.

```bash
./00-setup.sh                  # crea el clúster y deja todo listo
./01-step.sh && ./01-check.sh  # haga el paso, compruebe que quedó bien
./02-step.sh && ./02-check.sh
./99-teardown.sh               # borra el clúster y el espacio de trabajo
```

El verificador imprime `ok` cuando el paso quedó bien y sale con error cuando no. Los
`0N-step.sh` están para que no se quede atascado, pero el laboratorio se aprovecha leyendo el
`README.md` y escribiendo usted los comandos: corra el script para comparar.

### Su clúster de todos los días no se toca

Cada laboratorio crea sus propios clústeres kind, con su propio archivo de kubeconfig en
`~/ckne-lab/pNN/kubeconfig`, y **todos** los `kubectl` del laboratorio pasan `--kubeconfig`
de forma explícita. Su `~/.kube/config` no se lee ni se modifica, y el `99-teardown.sh` borra
únicamente los clústeres de ese laboratorio, por nombre. Sus otros clústeres de kind siguen
donde estaban.

Algunos pasos rompen a propósito la red del clúster del laboratorio para que usted encuentre
la falla. Use una máquina de práctica. Nunca corra en producción un comando de un libro, de un
blog o de un video sin entender qué hace. Este libro incluido.

### Qué hace cada laboratorio

| | Capítulos | Laboratorio |
|---|---|---|
| 1 | 1 y 2 | levante el aeropuerto de práctica con tres terminales y sin pistas, tienda los pasillos de Calico, y demuestre que el reglamento de la red se cumple entre terminales |
| 2 | 3 a 5 | una terminal con la pista rota, el inspector de paquetes que encuentra la falla, y una segunda puerta de abordaje con Multus |
| 3 | 6 a 9 | una cabina con su lista de extremos, el despachador que la copia en cada nodo, un directorio que deja de contestar y una entrada con la Gateway API |
| 4 | 10 a 12 | un grupo de modelos con su elector, un turno que sale con dirección fija, una ruta anunciada por BGP y dos clústeres que comparten una Service |
| 5 | 13 a 16 | quién entra a una zona, qué viaja cifrado entre nodos, un candado que emite cert-manager y la identidad de cada Pod |
| 6 | 17 y 18 | el tablero de la torre cuenta lo que pasó y una petición se sigue por su número |

### Si algo no funciona

Revise primero el `README.md` del laboratorio (sección de problemas frecuentes). Si el
problema sigue, abra un issue contando qué comando falló, con la versión de Kubernetes y el
sistema operativo. Los reportes de error son bienvenidos.

---

## English

### The book

**Here's What's Actually Going On with Kubernetes Networking.** *The complete Kubernetes networking guide in plain language.*
Eighteen chapters in six parts, with one lab per part. It covers the domains of the **CKNE**
(Certified Kubernetes Network Engineer) certification: core infrastructure and CNI, service
networking and DNS, advanced traffic management, network security and policy, and
observability. It makes the same bet as the rest of the series: once you understand the
mechanism, there is no answer left to memorize. The analogy is an airport, with its runways,
its numbered gates, its flight directory, its security checkpoint and its control tower.

Independent study material. Not affiliated with, endorsed by, or sponsored by the Linux
Foundation or the Cloud Native Computing Foundation. The labs emulate the certification's
format (tasks graded on the final state of the cluster) and never its content.

### What these labs are

Each lab is 50 to 60 minutes of real work against a real cluster (kind, inside Docker). Each
step gives you an objective and a deliverable, and is graded on the **final state of the
cluster**, not on what you typed or the path you took. The last step of each lab gives only
the objective, with no published solution. Each lab is published here only after a complete
run on kind, from start to finish.

### When to do each lab

There is one lab per part of the book, and each one uses **everything** in that part, not
just the last chapter. The moment to do it is when you finish the whole part.

| Finish reading | Then run | Time | Points |
|---|---|---|---|
| Chapter 2, *The Airport Rulebook and the Practice Runway* (closes Part I) | `en/lab-part-01` | 50 min | 50 |
| Chapter 5, *The Baggage Inspector's Magnifying Glass* (closes Part II) | `en/lab-part-02` | 60 min | 60 |
| Chapter 9, *The Terminal's Main Entrance through the Gateway API* (closes Part III) | `en/lab-part-03` | 60 min | 60 |
| Chapter 12, *Two Airports That Talk to Each Other* (closes Part IV) | `en/lab-part-04` | 60 min | 70 |
| Chapter 16, *Every Pod's Passport* (closes Part V) | `en/lab-part-05` | 60 min | 70 |
| Chapter 18, *Following the Suitcase and Reading the Flight Log* (closes Part VI) | `en/lab-part-06` | 60 min | 70 |

### Before you start

You need a Linux machine with these tools installed and working:

| Tool | What for | Version this was tested on |
|---|---|---|
| `docker` | running the clusters' nodes | 29.10.0 |
| `kind` | creating the practice clusters | v0.33.0 |
| `kubectl` | talking to the cluster | v1.37.0 |
| `helm` | installing components from Part IV on | v4.3.0 |
| `jq` | reading the cluster's answers in the graders | 1.7 |
| `curl` | downloading and probing endpoints from Part II on | 8.5.0 |
| `openssl` | inspecting certificates in Part V | 3.0.13 |
| `tar`, `sha256sum`, `base64`, `od` | unpacking downloads and comparing fingerprints | your distribution's |

Nearby versions are fine too. The clusters are created from the `kindest/node:v1.37.0` image
pinned by digest, and the labs need internet access when they are set up. The free memory each
lab asks for goes from 4 GB (Parts I and II) to 12 GB (Part IV) and 14 GB (Part V), because
those two bring up several clusters at once. Each `README.md` says what else that lab uses.

### Start here

```bash
git clone https://github.com/lfarizav/lo-que-pasa-es-que-redes-kubernetes.git
cd lo-que-pasa-es-que-redes-kubernetes/en/lab-part-01
cat README.md
```

The repository has two folders: `es/` (Spanish) and `en/` (English). The scripts are the
same; what changes is the language of each lab's `README.md`. Every lab runs the same way:
setup, each step with its grader, and teardown.

```bash
./00-setup.sh                  # creates the cluster and gets everything ready
./01-step.sh && ./01-check.sh  # do the step, then check that it landed
./02-step.sh && ./02-check.sh
./99-teardown.sh               # deletes the cluster and the workspace
```

The grader prints `ok` when the step is right and exits with an error when it is not. The
`0N-step.sh` scripts are there so you never get stuck, but you get the most out of a lab by
reading its `README.md` and typing the commands yourself: run the script to compare.

### Your everyday cluster is never touched

Each lab creates its own kind clusters with their own kubeconfig file at
`~/ckne-lab/pNN/kubeconfig`, and **every** kubectl in the lab passes `--kubeconfig`
explicitly. Your `~/.kube/config` is neither read nor modified, and `99-teardown.sh` deletes
only that lab's clusters, by name. Your other kind clusters stay where they were.

Some steps break the lab cluster's network on purpose so you can find the fault. Use a
practice machine. Never run a command from a book, a blog or a video on a production cluster
without understanding what it does. This book included.

### What each lab does

| | Chapters | Lab |
|---|---|---|
| 1 | 1 and 2 | build the practice airport with three terminals and no runways, lay Calico's corridors, and prove the network rulebook holds between terminals |
| 2 | 3 to 5 | a terminal with a broken runway, the packet inspector who finds the fault, and a second boarding door with Multus |
| 3 | 6 to 9 | the cabina namespace with its endpoint list, the dispatcher that copies it on every node, a directory that stops answering and an entrance with the Gateway API |
| 4 | 10 to 12 | a pool of models with its picker, a shift that leaves with a fixed address, a route announced over BGP and two clusters sharing a Service |
| 5 | 13 to 16 | who gets into a zone, what travels encrypted between nodes, a padlock cert-manager issues and every Pod's identity |
| 6 | 17 and 18 | the tower's board counts what happened and a request is followed by its number |

### If something does not work

Check the lab's `README.md` first (troubleshooting section). If the problem persists, open an
issue saying which command failed, with your Kubernetes version and operating system. Bug
reports are welcome.

---

_Creado con ❤️ por Luis Felipe Ariza Vesga._
