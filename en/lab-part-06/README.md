# Part VI - Lab: the tower's board counts what happened and a request is followed by its number

- Time: 60 min
- Points: 70

## Objective

This is an Exam-Style lab: each step tells you only the objective and the deliverable, and the step's command sequence lives in its cmd field for you to reveal after trying on your own. The exception is Step 7: it states the objective only, no command is published anywhere in the repository, and its check depends on a token that is different on every run. Everything happens in a single kind cluster, `ckne-lab6-torre`, with two nodes, Cilium 1.20.5, Istio 1.32.0 and Prometheus 3.16.0. Step 1 sets up the tower and asks the board who reports and which versions run (Chapter 17). Step 2 sends through the entrance an order with a number of good and failed responses that changes on every run, and reads it in the raw counters (Chapter 17). Step 3 closes the way to a Pod and counts in Cilium the packets the policy dropped (Chapter 17). Step 4 puts a second application behind the same entrance and spreads its fast and slow responses over the histogram's buckets (Chapter 17). Step 5 sets up Jaeger and the Collector, turns on tracing and the access log for the whole mesh and follows a request from its access-log line to its trace (Chapter 18). Step 6 runs `inyectar-falla.sh`, a script that blindly breaks a second application of the mesh: its content is encoded on purpose, as a courtesy blindfold and not as a real secret; you diagnose in Chapter 18's reading order and repair it (Chapter 18). Step 7 is the exam in miniature: an access log with one more key in a single proxy, with no published command (Chapter 18).

## Prerequisites

- A Linux machine with kind, kubectl, docker, helm, jq, curl, tar, sha256sum, base64 and od on the PATH, and with at least 6 GB of free RAM: the lab brings up two kind nodes in one cluster, `ckne-lab6-torre`, and deletes it in the teardown.
- ISOLATION. This lab's cluster NEVER touches your usual kubeconfig: it is created with --kubeconfig ~/ckne-lab/p05/kubeconfig from the first command, and every kubectl, helm and istioctl of the lab passes that file and an explicit context. Helm is used with --repo, so no repositories are added to your Helm configuration either.
- Internet access during the whole lab: kind downloads the node image; Helm downloads Cilium from helm.cilium.io and Prometheus from prometheus-community.github.io; Step 1 downloads the Gateway API CRDs and the istioctl 1.32.0 binary from github.com (with its checksum verified); Docker pulls go-httpbin, curl, Jaeger and the OpenTelemetry Collector. The guided path of Steps 1 to 6 took 6 minutes of machine time (359 s) in the verification run, almost half of it in Step 1; the rest of the 60 minutes is reading, the deliverables and Step 7, which was not timed with a person. The 6 GB of RAM is an estimate, not a measurement, and disk space was not measured.
- A cluster with names the chapters do not use: none of the namespaces or Gateways of these pages repeat here, and of the applications only `jaeger` and `colector`, which Chapter 18 also uses for the two tracing tools. What does repeat are the tools and the versions: Cilium 1.20.5, Istio 1.32.0, Gateway API v1.6.1, the prometheus Helm chart 29.48.0, Jaeger 2.23.0 and the Collector 0.165.0.
- The steps depend on each other and in order: all use Step 1's cluster, Steps 2 and 4 read the counters of the `entrada-torre` entrance, and Steps 6 and 7 use the mesh, Jaeger and the access log that Step 5 sets up. This run's numbers are in `~/ckne-lab/p05/pedido.txt` and Step 7's token in `~/ckne-lab/p05/ficha-de-la-bitacora.txt`; the setup writes them and they change on every run.

## Steps

The `0N-step.sh` is there so you never get stuck: read the step, try it on your own first, and run the script when you want to compare. It also writes the answer file the step asks for, reading the values from the live cluster.

### 1. Ch. 17: The tower standing and the board that says who reports (10 pts)

Objective: the `ckne-lab6-torre` cluster (one control plane and one worker, node v1.37.0, without kind's CNI) with Cilium 1.20.5 and its metrics on, kube-proxy publishing its metrics on every interface of the node, Gateway API v1.6.1, Istio 1.32.0 with the minimal profile and two providers in the mesh configuration (`trazador`, OTLP over gRPC to `colector.registro.svc.cluster.local` on port 4317, and `registro-json`, a JSON access log to /dev/stdout with the seven keys respuesta, bandera, motivo, nombre, ruta, traza and ms) and Prometheus from chart 29.48.0 in the `vigilancia` namespace, scraping every 10 seconds and with a `kube-proxy` job of its own. In `faena`, the `bodega` application (go-httpbin 2.26.0) behind the `entrada-torre` Gateway with the name `bodega.torre.test`; in `externo`, the `sondeo` Pod, from where everything is asked. Deliverable: `01-respuesta.txt` with PROMETHEUS, COREDNS, CILIUM and ISTIO (the version the board reports for each one) and OBJETIVOS_KUBE_PROXY (how many targets of that job are up).

Chapter 17 left a method: before reading a number, ask whether the instrument answers. Here the versions are not copied from the documentation: they are asked of the board, which reads them from each component's metrics. `pregunta.sh`, which the step leaves in the workspace, sends a PromQL query to Prometheus from `sondeo` and writes one line per series.

<details>
<summary>Grader hint (check_hint)</summary>

The check demands both nodes Ready at v1.37.0, the Cilium v1.20.5 daemonset with two ready Pods, istiod 1.32.0, the Gateway API v1.6.1 CRDs, the prometheus-29.48.0 Helm release in vigilancia, bodega with its replica ready, `entrada-torre` Programmed and `sondeo` Running. Then it asks the board live: two kube-proxy targets up and series of the four version metrics. Finally it compares each line of `01-respuesta.txt` with what the board says now; writing the versions from memory is not enough if the board does not report them.

</details>

<details>
<summary>What you should see</summary>

kind create ends with Set kubectl context to `kind-ckne-lab6-torre`, the cilium daemonset ends with successfully rolled out, istioctl prints Installation complete, and bodega, `entrada-torre` and `sondeo` end up ready. After 40 seconds, count by (job) (up) gives four jobs, among them kube-proxy 2 and prometheus 1. The versions, read from the board: prometheus_build_info 3.16.0 1, coredns_build_info 1.14.6 2, cilium_version 1.20.5 2 and, on the istio_build line, 1.32.0 2. `01-respuesta.txt` ends up with PROMETHEUS=3.16.0, COREDNS=1.14.6, CILIUM=1.20.5, ISTIO=1.32.0 and OBJETIVOS_KUBE_PROXY=2.

</details>

```bash
./01-step.sh
./01-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 2. Ch. 17: This run's order, read in the entrance's raw counters (10 pts)

Objective: send through the `entrada-torre` Gateway, with the name `bodega.torre.test`, exactly PEDIDO_200 requests that answer 200 and PEDIDO_503 that answer 503 (both numbers are in `pedido.txt` and change on every run), and read them in the Istio request counter the entrance's proxy writes. Deliverable: `02-respuesta.txt` with PETICIONES_200, PETICIONES_503 and RAZON_DE_ERRORES (the 503s over the total, with three decimals).

Chapter 17 showed that a rate over a range is extrapolated and may not give the number that was sent, and that to count one by one the raw counter, read before and after, works better. go-httpbin answers on /status/:code with the code it is asked for. The check counts everything the entrance's proxy recorded toward bodega: one extra test request is counted too.

<details>
<summary>Grader hint (check_hint)</summary>

The check asks the board live for the same counter and demands that it says exactly PEDIDO_200 responses 200 and PEDIDO_503 responses 503 toward bodega, with no other code. Then it compares the three lines of `02-respuesta.txt` with those counters. A number copied from a rate, or an order with extra requests, does not match.

</details>

<details>
<summary>What you should see</summary>

The before reading prints nothing (the cmd gives it no header): nobody has asked bodega anything yet. The output starts at the DESPUES: line. After the burst and 30 seconds, sum by (response_code) (istio_requests_total{reporter="source",destination_service_name="bodega"}) prints two lines, 200 with PEDIDO_200 and 503 with PEDIDO_503 (in the author's run, 200 17 and 503 3), and the error ratio is 503/(200+503) with three decimals (0.150 with those numbers). `02-respuesta.txt` ends up with those three lines.

</details>

```bash
./02-step.sh
./02-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 3. Ch. 17: The packets the policy dropped, counted by Cilium (10 pts)

Objective: a NetworkPolicy in `faena` that leaves the `bodega` Pods with no allowed ingress at all; INTENTOS_BLOQUEADOS direct requests from `sondeo` to the `bodega` Service while it is in place (the number is in `pedido.txt`); and the policy removed at the end, with `bodega` answering again. Deliverable: `03-respuesta.txt` with CAIDAS_ENTRANTES_NEGADAS (what Cilium's drop counter says for ingress and the policy denied reason) and CODIGO_SIN_LA_POLITICA (the HTTP code of a direct request after removing it).

In Chapter 17 Cilium's drop counter counted packets, not requests. Here the question is the same: how many packets fell, not how many requests failed. Read the counter by direction and reason before and after.

<details>
<summary>Grader hint (check_hint)</summary>

The check demands that no NetworkPolicy is left in faena and that a direct request from `sondeo` gets 200. Then it reads live the ingress drop counter with the Policy denied reason: it has to exist, it cannot be lower than INTENTOS_BLOQUEADOS and it has to match CAIDAS_ENTRANTES_NEGADAS. If you never applied the policy, the series does not exist and the step fails.

</details>

<details>
<summary>What you should see</summary>

Before the policy, sum by (direction, reason) (cilium_drop_count_total) has only one egress series, EGRESS Unsupported L3 protocol, whose origin this lab does not investigate. With `corta-paso` in place, each attempt prints 000 exit 28 (the 2-second limit runs out). Afterwards the INGRESS Policy denied series shows up with at least one packet per attempt (in the author's run, 12 packets for 6 attempts). After deleting the policy, the direct request gets 200. `03-respuesta.txt` ends up with CAIDAS_ENTRANTES_NEGADAS equal to that counter and CODIGO_SIN_LA_POLITICA=200.

</details>

```bash
./03-step.sh
./03-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 4. Ch. 17: The histogram's buckets before the quantile (10 pts)

Objective: in `faena`, a second application `pesaje` (go-httpbin 2.26.0, Service on port 80) behind the same `entrada-torre` Gateway with the name `pesaje.torre.test` and the `ruta-pesaje` HTTPRoute; PESAJES_RAPIDOS requests to /get and PESAJES_LENTOS to /delay/2 through that entrance (the numbers are in `pedido.txt`). Deliverable: `04-respuesta.txt` with HASTA_1000_MS and HASTA_2500_MS (what those two buckets of the entrance's duration histogram toward pesaje count), ENTRE_1000_Y_2500_MS (the difference) and OBSERVACIONES (the +Inf bucket).

Chapter 17 closed with a habit: before trusting a quantile, look at the buckets around it. A quantile comes out of an interpolation inside a bucket; the buckets say how many observations fell up to each limit. A separate application keeps this step's counts apart from Step 2's.

<details>
<summary>Grader hint (check_hint)</summary>

The check demands pesaje with its replica ready and `ruta-pesaje` attached to `entrada-torre` with the name `pesaje.torre.test` toward the pesaje Service. Then it reads live the entrance's buckets toward pesaje: the 1000 one has to count PESAJES_RAPIDOS, +Inf the sum of both numbers, and the difference between 2500 and 1000, PESAJES_LENTOS. The four lines of `04-respuesta.txt` have to match those buckets.

</details>

<details>
<summary>What you should see</summary>

The fast requests print 200 with a few milliseconds of time_total and the slow ones 200 with a little over 2 seconds (in the author's run, between 2.0021 and 2.0040). After 30 seconds, sum by (le) (istio_request_duration_milliseconds_bucket{reporter="source",destination_service_name="pesaje"}) sorted with sort -g counts PESAJES_RAPIDOS up to the 1000 bucket, PESAJES_RAPIDOS plus PESAJES_LENTOS from the 2500 one up to +Inf, and nothing in between. In the author's run: 1000.0 8, 2500.0 14 and +Inf 14. `04-respuesta.txt` ends up with HASTA_1000_MS=8, HASTA_2500_MS=14, ENTRE_1000_Y_2500_MS=6 and OBSERVACIONES=14 for those numbers.

</details>

```bash
./04-step.sh
./04-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 5. Ch. 18: From the access-log line to the whole trace (10 pts)

Objective: in the `registro` namespace, Jaeger 2.23.0 (OTLP over gRPC on 4317 and the query on 16686) and the Collector 0.165.0 that forwards traces to it, at the address the `trazador` provider of Step 1 expects; a `todo-el-trafico` Telemetry in `istio-system` that traces one hundred percent with `trazador` and writes the access log with `registro-json`; in `trazado`, with Istio injection, the `paquetes` application behind the `entrada-trazas` Gateway with the name `paquetes.torre.test`; and one request from `sondeo` with this run's mark (`marca.txt`) in the path. Deliverable: `05-respuesta.txt` with TRAZA (the trace number the entrance wrote for that request), TRAMOS (how many spans Jaeger keeps for it) and TRAMO_RAIZ (the identifier of the span without a parent).

Chapter 18 read one request three times: in the entrance's line, in the application proxy's line and in the trace that joins them by the number. The mark in the path lets you pick its line among all the lines of the log.

<details>
<summary>Grader hint (check_hint)</summary>

The check demands the mesh-wide `todo-el-trafico` Telemetry with `trazador` at one hundred percent and `registro-json`; the paquetes Pods with istio-proxy among the init containers; in the entrance's log, a line with this run's mark, code 200 and the TRAZA number; a line of paquetes' sidecar with that same number; and in Jaeger that trace with a single root span and a paquetes server span whose parent is a client span of the entrance. TRAMOS and TRAMO_RAIZ have to match what Jaeger returns now.

</details>

<details>
<summary>What you should see</summary>

Jaeger and colector end with successfully rolled out, the `todo-el-trafico` Telemetry is created, paquetes and `entrada-trazas` end up ready and the marked request gets 200. The entrance's JSON line carries bandera -, motivo via_upstream, the name `paquetes.torre.test`, the path with the mark and a 32-hex-digit trace number; paquetes' sidecar writes its own line with the same number. Jaeger returns three spans: `entrada-trazas-istio.trazado` SERVER without a parent (the root), `entrada-trazas-istio.trazado` CLIENT child of the root, and paquetes.trazado SERVER child of the client span. `05-respuesta.txt` ends up with TRAZA, TRAMOS=3 and TRAMO_RAIZ.

</details>

```bash
./05-step.sh
./05-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 6. Ch. 18: An application that does not answer, diagnosed in the chapter's reading order (10 pts)

Objective: in `trazado`, the `consigna` application (Deployment, Service and the `ruta-consigna` HTTPRoute toward the `entrada-trazas` Gateway with the name `consigna.torre.test`) answers 200 on /get to `sondeo`. Today it does not answer: `inyectar-falla.sh` leaves it broken. Locate the fault by reading in Chapter 18's order, repair it without deleting or recreating any object and leave the diagnosis written. Deliverables: `06-diagnostico.txt`, with one section per reading (== 1. what the client saw, == 2. the entrance's access-log line, == 3. the state of the objects that line points at) and `06-respuesta.txt` with CODIGO_DEL_CLIENTE, BANDERA and MOTIVO (those of that line), OBJETO_REPARADO (type/name of the object that changed) and VALOR_QUE_LA_FALLA_DEJO (the wrong value you found, as you read it in the object).

Chapter 18 left a reading order: first the code the client saw, then the access-log line with its flag and its reason, then the state of the objects that line points at. Each reading narrows the next one. Read what the line says, not what you expect to see.

<details>
<summary>Grader hint (check_hint)</summary>

This step's shortcut is deleting what broke and creating it again. The check closes that: it demands that `06-diagnostico.txt` is newer than the fault and carries the three sections, with the code the client saw in the first, in the second the log's JSON line for `consigna.torre.test` with its code, its flag and its reason, and that line has to exist in the entrance's log, and in the third the value the fault left; that the object you repaired is the same one the fault left (its identity is compared with the one the fault script saved), that everything still leads to the consigna application and that the entrance answers 200 now. The five lines of `06-respuesta.txt` have to match what the fault left.

</details>

<details>
<summary>What you should see</summary>

`inyectar-falla.sh` prints falla inyectada. THE SYMPTOM: `sondeo` requests `consigna.torre.test` and gets 503. The entrance's log line for that name carries respuesta 503, bandera UH and motivo no_healthy_upstream: according to Envoy's format manual, UH means there were no healthy upstream hosts in the destination cluster, in addition to the 503 code. The route is fine (Accepted True and ResolvedRefs True), so it is not a route toward a destination that does not exist like the chapter's. The consigna Service exists but has no ready endpoints: it asks for `app=consigna-v2` and the consigna Pods carry app=consigna. The repair is for the Service to ask for the label the Pods carry (a patch, without recreating it): a ready endpoint appears and the entrance returns 200. `06-respuesta.txt` ends up with CODIGO_DEL_CLIENTE=503, BANDERA=UH, MOTIVO=no_healthy_upstream, OBJETO_REPARADO=service/consigna and `VALOR_QUE_LA_FALLA_DEJO=app=consigna-v2`.

</details>

```bash
./06-step.sh
./06-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

### 7. Ch. 18: One more key in a single proxy's log, with the objective only (unsolved point) (10 pts)

The exam does not give you the command: it gives you a task written as an objective. This step is that situation in small: it carries no recipe, and the setup left the token in a file that changes on every run, like the piece of data the exam puts in the statement. There is no answer file either: what is graded is the state of the cluster.

The objective is written as a comment at the end of the step's cmd. Read it calmly, write on one line each condition that has to hold, and build the end state one at a time. A configuration change takes time to reach the proxies: when something does not show up, repeat the request watching the clock before changing anything else.

<details>
<summary>Grader hint (check_hint)</summary>

This is the unsolved point: the check fails on the guided state of Steps 1 to 6 because no proxy writes the ficha key, until you solve it. The check repeats its requests with waits for several minutes before it fails. The shortcuts it closes: editing the token (it is compared with a fingerprint the setup saved apart) and writing the key in other proxies too: the check reads both entrances and consigna, and checks what the objective says stays the same. The check's requests carry new tokens on every run, so an old line is not enough: paquetes' proxy has to write the token of the request that arrives now.

</details>

<details>
<summary>What you should see</summary>

This step's command sequence is not published: it is the unsolved point. The correct end state: the proxy of the paquetes Pods writes, for each request, a JSON line with the eight keys (bandera, ficha, motivo, ms, nombre, respuesta, ruta and traza), and ficha carries the value of the x-ficha header; both entrances and consigna's proxy keep the seven keys of Step 1; the configuration Step 5 left for the whole mesh stays as it was; and in paquetes' log there is a line with this run's token whose trace Jaeger keeps with a paquetes span. The check sends its own requests with new tokens and repeats with the elapsed time in view until the change arrives.

</details>

```bash
./07-step.sh
./07-check.sh
```

The grader prints `ok` and exits 0 when the step is right, and exits 1 when it is not. It does not take your word for it: it queries the live cluster again.

## How to run it

```bash
./00-setup.sh                  # creates the cluster and sets everything up
./01-step.sh && ./01-check.sh  # do the step, check it landed
./02-step.sh && ./02-check.sh
./03-step.sh && ./03-check.sh
./04-step.sh && ./04-check.sh
./05-step.sh && ./05-check.sh
./06-step.sh && ./06-check.sh
./07-step.sh && ./07-check.sh
./99-teardown.sh               # deletes the cluster and the workspace
```

## Troubleshooting

- **Symptom (step 1):** count by (job) (up) has no kube-proxy job, or its targets at 0
  **What to do:** kube-proxy publishes its metrics on 127.0.0.1 unless metricsBindAddress is changed, and Prometheus runs in another Pod. Look at the kind cluster configuration you created the tower with and at the kube-proxy job in the Prometheus values; if you changed the cluster, it has to be created again.

- **Symptom (step 1):** `pregunta.sh` prints nothing
  **What to do:** Prometheus scrapes every 10 seconds and needs at least one scrape of each target. Wait half a minute and repeat; if it stays empty, check that the `prometheus-server` Pod is 2/2 in vigilancia.

- **Symptom (step 2):** The counter says more requests than the order
  **What to do:** Some test request was counted. The counter lives in the entrance's proxy: restart the `entrada-torre-istio` Deployment in faena, wait until it is ready and send the order only once. That also erases what Step 4 may have counted, so do it before that step.

- **Symptom (step 2):** No series shows up after the burst
  **What to do:** Check that each request carries the Host: `bodega.torre.test` header and goes to the `entrada-torre-istio.faena` Service; without the name, the route does not take it. Wait two more scrapes before concluding.

- **Symptom (step 3):** The blocked requests get 200
  **What to do:** The policy takes a few seconds to reach the agent. Wait five seconds after the apply and check that its podSelector picks the bodega Pods and that policyTypes includes Ingress.

- **Symptom (step 3):** The counter changed between the reading and the check
  **What to do:** Every blocked attempt adds packets. If you repeated attempts with the policy in place, read the counter again and write the new value in `03-respuesta.txt`.

- **Symptom (step 4):** The slow ones show up in the 1000 bucket
  **What to do:** Look at the path you requested: /delay/2 takes two seconds. In a test run of the author's, /delay/1 was counted up to 1000 milliseconds at the entrance, although curl measured a little over one second; with two seconds there is no doubt about the bucket.

- **Symptom (step 4):** The buckets count more than the order
  **What to do:** Some test request was counted. Restart the `entrada-torre-istio` Deployment, wait until it is ready and send Step 2's order and this step's once each.

- **Symptom (step 5):** Jaeger returns an error or no spans for the number
  **What to do:** The spans take a few seconds to go through the Collector. Wait ten seconds and repeat the query. If it stays empty, look at the colector Pod's log in registro: the exporter has to reach jaeger.registro on 4317.

- **Symptom (step 5):** The entrance's log has no lines that start with {
  **What to do:** The JSON log comes from the `registro-json` provider, which the `todo-el-trafico` Telemetry turns on. Check that the Telemetry is in istio-system and that the request was made after creating it.

- **Symptom (step 5):** Jaeger lost the trace
  **What to do:** All-in-one Jaeger keeps traces in memory: if its Pod restarted, the earlier ones are gone. Send another marked request and write `05-respuesta.txt` with the new number.

- **Symptom (step 6):** I cannot find consigna's line in the entrance's log
  **What to do:** The log belongs to the `entrada-trazas` Gateway's Pod, in trazado. Filter the lines that start with { and pick with jq the one for the name `consigna.torre.test`; wait a few seconds after the request.

- **Symptom (step 6):** After repairing I still do not get 200
  **What to do:** The proxies take a few seconds to learn about the change. Wait ten seconds, repeat the request and read the log line again: if the flag changed, the reading changed too.

- **Symptom (step 6):** The Step 6 check fails although the application already answers 200
  **What to do:** If you ran `inyectar-falla.sh` again, the fault marker is now newer than your diagnosis. Read the three sections again, repair again and rewrite `06-diagnostico.txt` and `06-respuesta.txt`.

- **Symptom (step 7):** The ficha key does not show up in paquetes' log
  **What to do:** Look at the clock first: repeat the request every ten seconds for a minute before changing anything. Then read what you applied with kubectl get and compare it, field by field, with the objective.

- **Symptom (step 7):** My token shows up, but the check says no
  **What to do:** The check also reads the other lines: request through both entrances and to consigna, and count the keys of each line. Compare the token with the content of `~/ckne-lab/p05/ficha-de-la-bitacora.txt`: any extra character changes the value.

## Going further

- In Step 4, ask for histogram_quantile(0.9, ...) over the same buckets with a two-minute rate right after the order and again five minutes later. Note both values and explain with Prometheus' functions page what sets them apart.
- In Step 3, leave the policy in place and read the drops with Hubble from the Cilium agent, as in Chapter 18. Compare how many DROPPED flows it sees with what cilium_drop_count_total counts. This changes the counter Step 3's check measures: do it after checking the steps.
- In Step 5, stop sampling at 100 percent and send another marked request. Look at which trace number the entrance writes and whether Jaeger keeps it. This may change what the checks of Steps 5 and 7 measure: do it after checking them and put the sampling back as it was when you finish.

## References

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
