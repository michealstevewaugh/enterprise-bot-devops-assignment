# Findings — Part 4 debug lab

Fill in one entry per defect you find. Paste the *actual* output you saw —
we cross-check it against your session recording and your git diff, and the
diagnostic path matters more to us than the fix itself.

Before you start investigating, begin recording:
`script -q part4-session.log` (or `asciinema rec part4-session.cast`), and
commit that file alongside this one.

---

## Defect 1

**Symptom:** The backend pod is not starting successfully.

**Cause:** The pod security context requires a non-root user, but the image specifies the user by name (`nonroot`), so Kubernetes cannot verify it is non-root from the image metadata.

**Fix:** Specify the verified numeric UID `65532` using `runAsUser`.

**How I found it** (the sequence of commands/reasoning that led you here):

1. Inspected pod status and events using `kubectl -n debug-lab get pods` and `kubectl -n debug-lab get events --sort-by=.lastTimestamp`.
2. The event reported: `container has runAsNonRoot and image has non-numeric user (nonroot), cannot verify user is non-root`.
3. Inspected `broken-chart/templates/backend.yaml` and identified the security-context configuration.
4. Updated the chart to use numeric UID `65532` and verified the workload again.

---

## Defect 2

**Symptom:** The gateway cannot reach the backend using its configured backend URL.

**Cause:** `BACKEND_URL` points to `http://backend.default.svc:8080`, but the backend Service is deployed in the `debug-lab` namespace. The URL therefore points to the wrong namespace.

**Fix:** Configure `BACKEND_URL` to use `http://backend.debug-lab.svc:8080` for this lab.

**How I found it:**

1. Inspected `broken-chart/values.yaml` for the gateway's backend URL.
2. Checked the Services in the `debug-lab` namespace using `kubectl -n debug-lab get services`.
3. Compared the configured URL with the backend Service's namespace.
4. Corrected the URL and reran the lab verification.

---

## Defect 3

**Symptom:** The metrics workload cannot be scheduled under the lab's resource constraints.

**Cause:** The metrics container requests `2` CPUs and has a CPU limit of `4`, exceeding the `LimitRange` maximum of `1` CPU per container in the `debug-lab` namespace.

**Fix:** Set CPU requests and limits within the namespace guardrails. The corrected chart uses a request of `50m` and a limit of `200m`.

**How I found it:**

1. Inspected the metrics resources in `broken-chart/values.yaml`.
2. Read `cluster-state/limits.yaml` to identify the namespace's maximum permitted CPU and memory.
3. Compared the metrics resource settings against the configured maximum.
4. Reduced the CPU request and limit to permitted values and reran verification.

---

## Defect 4

**Symptom:** The migration Job cannot run successfully with its original pod configuration.

**Cause:** The Job pod template specifies `restartPolicy: Always`. Kubernetes Jobs require the pod restart policy to be `Never` or `OnFailure`.

**Fix:** Change the migration Job's `restartPolicy` to `Never` and retain the appropriate Job retry configuration.

**How I found it:**

1. Inspected `broken-chart/templates/migrate-job.yaml`.
2. Found `restartPolicy: Always` in the Job pod template.
3. Compared the configuration with Kubernetes Job requirements.
4. Changed the restart policy to `Never` and checked the Job status after redeployment.

---

## Defect 5

**Symptom:** The reporter does not have the intended permissions to list Pods in its namespace.

**Cause:** The RoleBinding references the `default` ServiceAccount instead of the `reporter` ServiceAccount used by the reporter Deployment. As a result, the intended Pod-read permissions are not bound to the application's identity.

**Fix:** Update the RoleBinding subject to use ServiceAccount `reporter` in the `debug-lab` namespace, retaining only the required Pod `get` and `list` permissions.

**How I found it:**

1. Inspected `broken-chart/templates/rbac.yaml`.
2. Compared the RoleBinding subject with the `serviceAccountName` in `broken-chart/templates/reporter.yaml`.
3. Found that the Deployment uses `reporter`, while the RoleBinding refers to `default`.
4. Corrected the binding and checked the permission using `kubectl auth can-i list pods -n debug-lab --as=system:serviceaccount:debug-lab:reporter`.

**Note:** Fixing this RBAC configuration did not resolve the separate reporter application-image defect documented in the unresolved section below.

---

## Defect 6

**Symptom:** The worker cannot write to the required temporary or cache directory when running with a read-only root filesystem.

**Cause:** The worker configuration enables `readOnlyRootFilesystem: true` but does not provide a dedicated writable volume for the application's required temporary/cache directory.

**Fix:** Add an `emptyDir` volume and mount it at the application's actual writable temporary/cache path, while retaining the read-only root filesystem and non-root security settings.

**How I found it:**

1. Inspected `broken-chart/templates/worker.yaml` and reviewed the container security context.
2. Checked whether the worker had a writable volume mounted at the directory used by the application.
3. Identified the need for dedicated writable storage without disabling the read-only root filesystem.
4. Added an `emptyDir` volume and mount at the verified path, then reran the lab verification.

---

If you ran out of time on any defect, say so here and describe what you would
have tried next — that section is read carefully and counts in your favour.

## Unresolved — reporter never becomes Ready (application-image defect)

**Status:** not fixed. No chart change was made for this, because the evidence
shows the cause is inside the image, and every chart-level workaround would
break a lab rule.

**Symptom**

```
$ ./scenario.sh verify
  FAIL  deployment reporter: 0/1 ready
  FAIL  reporter /report does not return a pod count
2 check(s) failing, 9 passing.
```

```
$ kubectl -n debug-lab logs deploy/reporter | head -3
2026/10/10 08:14:04 eb-debug-app 2.0.0 starting: mode=reporter pod=reporter-5c97c99584-6vjpt listening on :8080 (image default is 8081; set PORT to override)
2026/10/10 08:14:09 pod list failed: parse pod list: unexpected end of JSON input
2026/10/10 08:14:09 GET /healthz -> 503 (from 10.244.1.1:60764)

$ curl -i localhost:18080/report      # via kubectl port-forward to the reporter pod
HTTP/1.1 503 Service Unavailable
{"error":"parse pod list: unexpected end of JSON input","status":"unhealthy"}
```

**Ruled out (cluster side is healthy)**

- RBAC: `kubectl auth can-i list pods -n debug-lab --as=system:serviceaccount:debug-lab:reporter` → `yes`.
- Exact request replayed from a BusyBox pod running as SA `reporter`
  (`GET https://kubernetes.default.svc/api/v1/namespaces/debug-lab/pods?limit=100`,
  `Authorization: Bearer <SA token>`) → `HTTP/1.1 200 OK`, a complete, valid
  `PodList` (104273 bytes, pretty-printed for wget's User-Agent).
- The app checks the status code: a non-200 would be logged as
  `kubernetes API returned HTTP %d: %s`, which never appears. So it receives a
  200 and fails to parse the body.

**Cause**

`main.(*reporter).listPods` in `/eb-debug-app` reads the response through
`io.LimitReader(resp.Body, 1024)` before `json.Unmarshal`. Any response over
1 KiB is truncated, and Go reports truncated JSON as
`unexpected end of JSON input`. A real PodList cannot fit in 1 KiB:

```
$ kubectl get --raw "/api/v1/namespaces/debug-lab/pods?limit=100" | wc -c
   43208
$ kubectl get --raw /api/v1/namespaces/debug-lab/pods/migrate-qd7tg | wc -c   # smallest pod
    6838          # still 4361 bytes with metadata.managedFields removed
```

**How I found it** (read-only analysis; the image has no shell)

1. `docker image inspect` → distroless, single static Go binary `/eb-debug-app`.
2. `docker create` + `docker cp` to extract the binary (not executed in the cluster).
   `strings` shows the request template `%s/api/v1/namespaces/%s/pods?limit=100`,
   base `https://kubernetes.default.svc`, SA dir `/var/run/secrets/kubernetes.io/serviceaccount`.
3. The binary is stripped, but `.gopclntab` remains. Resolved
   `main.(*reporter).listPods` = `0x6a36c0–0x6a3e40` with Go's `debug/gosym`,
   then disassembled it with `objdump`:
   ```
   6a3b25: call runtime.newobject          ; new io.LimitedReader
   6a3b58: movq %rcx, 0x8(%rax)            ; .R = resp.Body
   6a3b5c: movq $0x400, 0x10(%rax)         ; .N = 1024
   6a3b6e: call io.ReadAll
   6a3b7b: cmpq $0xc8, 0x10(%rdx)          ; resp.StatusCode == 200
   6a3bd2: call encoding/json.Unmarshal    ; -> "parse pod list: %w"
   ```
   `newReporter` reads only `NAMESPACE` (env) plus the SA `namespace`, `ca.crt`, and `token`
   files. No env var or flag controls the URL, headers, or read limit.
4. Confirmed the behaviour, not just the disassembly: ran the real image locally
   in Docker (isolated network, not the cluster) against a fake TLS API server
   that returns a valid one-item PodList:
   ```
   body 1000 bytes -> /report: {"namespace":"debug-lab","pod":"3f150da755e0","pods":1}
   body 1100 bytes -> /report: 503 {"error":"parse pod list: unexpected end of JSON input","status":"unhealthy"}
   ```

**Why there is no chart fix.** The chart controls the SA, RBAC, env, probes,
resources, and volumes. None of them changes the size of the API server's
response. The only ways to get green would be:
- a different image or tag (forbidden),
- `hostAliases` or `HTTPS_PROXY` pointing `kubernetes.default.svc` at a
  response-trimming proxy, with a replaced CA mount (a MITM of the API, which
  bypasses the real pod-list call),
- weakening or removing the readiness probe.

All of these break the lab rules, so I did none of them.

**What I would do next.** Raise it with the image owners. The fix belongs in
the app: raise or remove the 1 KiB cap (or stream-decode the body), and/or ask
the API server for less data (`Accept: application/json;as=PartialObjectMetadataList;g=meta.k8s.io;v=v1`).
After that, the existing chart should go green without further changes.
