# DevOps / Platform Engineer Take-Home Assignment

## Project Overview

This repository contains a containerized HTTP application, a Helm chart for deploying it to Kubernetes, an automated local setup script, and a debugging lab submission.

The application exposes a JSON endpoint containing its application name, version, and hostname, together with a health-check endpoint for Kubernetes probes.

## Repository Structure

```text
.
├── setup.sh
├── README.md
├── ANSWERS.md
├── service/
├── chart/
└── lab/
    ├── scenario.sh
    ├── cluster-state/
    ├── broken-chart/
    ├── FINDINGS.md
    └── part4-session.log
```

## Prerequisites

Install the following tools before running the project:

- Docker
- kind
- kubectl
- Helm
- curl

The setup script creates or reuses a local kind cluster named `demo`, installs ingress-nginx, builds and loads the application image, and deploys the Helm release.

## How to Run

From the repository root:

```bash
chmod +x setup.sh
./setup.sh
```

The script configures the local Kubernetes cluster, deploys the application into namespace `demo`, and performs an HTTP request through the Ingress.

The script is designed to reuse an existing kind cluster and use Helm's `upgrade --install` operation for repeatable deployments.

## How to Verify

### 1. Check the Kubernetes resources

```bash
kubectl get nodes
kubectl get pods -n demo
kubectl get svc -n demo
kubectl get ingress -n demo
```

### 2. Check the application endpoint

The setup script maps the ingress controller to localhost and configures the request to resolve `demo.local` to `127.0.0.1`.

```bash
curl --noproxy '*' \
  --resolve demo.local:80:127.0.0.1 \
  http://demo.local/
```

The response should be JSON containing the configured application name, version, and pod hostname.

### 3. Check application health

```bash
kubectl port-forward -n demo svc/demo 8080:80
```

In another terminal:

```bash
curl http://127.0.0.1:8080/healthz
```

Stop the port-forward process with `Ctrl+C` when finished.

### 4. Verify Helm configuration

```bash
helm list -n demo
helm get values demo -n demo
```

To inspect the rendered chart with overridden values:

```bash
helm template demo ./chart \
  --set replicaCount=3 \
  --set config.appName=override-test \
  --set config.version=2.0.0
```

Review the rendered Deployment and ConfigMap to confirm that the overrides are applied.

## Resource Requests and Limits

The chart defaults are:

| Resource | Request | Limit |
|---|---:|---:|
| CPU | 50m | 200m |
| Memory | 64Mi | 128Mi |

These values are intended as lightweight starting points for a small demonstration service running locally. The CPU request reserves a small scheduling amount, while the limit caps CPU usage. The memory request supports scheduling, and the memory limit constrains container memory consumption.

These are not production sizing guarantees. Actual values should be validated using representative workload tests and observed resource usage.

The default replica count is two. Liveness and readiness probes use `/healthz`. Application configuration is supplied through a ConfigMap using the `APP_NAME` and `VERSION` environment variables.

## Deliberately Skipped and Associated Risks

This is a local take-home implementation rather than a production deployment.

- **TLS:** The local Ingress uses HTTP. Production traffic should use TLS with managed certificate renewal.
- **Autoscaling:** Horizontal Pod Autoscaling is disabled by default. A variable workload may require autoscaling and capacity planning.
- **Production observability:** Centralized logs, metrics, dashboards, and alerting are not fully configured. Failures may take longer to diagnose.
- **Supply-chain security:** Automated image vulnerability scanning, image signing, and SBOM generation are not integrated into the basic setup.
- **High availability:** A local kind cluster does not provide production-grade infrastructure resilience.
- **Network and access controls:** Production deployment would require appropriately configured network policies, least-privilege RBAC, and restricted access.

## Production Readiness Improvements

For production use, I would:

1. Run automated CI checks for application tests, Docker builds, Helm linting, and chart rendering.
2. Scan images for vulnerabilities and pin production images to immutable digests.
3. Configure TLS, DNS, and a supported ingress or Gateway API implementation.
4. Add centralized observability, actionable alerts, and service-level indicators.
5. Validate requests, limits, and autoscaling thresholds under realistic load.
6. Apply least-privilege RBAC, network policies, and security contexts.
7. Add deployment rollback procedures and test backup and disaster-recovery plans.
8. Validate deployment idempotency and recovery from partial failures.

## Part 4 — Debugging Lab

The `lab/` directory contains the supplied debugging scenario, its environment state, the chart being investigated, findings, and the terminal session recording.

The original `lab/scenario.sh` and `lab/cluster-state/` files should remain unchanged. Fixes belong in `lab/broken-chart/`.

To run the lab:

```bash
cd lab
./scenario.sh up
./scenario.sh verify
```

The verification should be run against the intended lab cluster and environment. The findings and recording should document the actual diagnostic process and observed output, including any unresolved issue.

## How I Used AI

I used ChatGPT selectively during the assignment, mainly to help investigate complex Kubernetes and Helm issues that required deeper technical analysis. Since I already have hands-on experience with DevOps, Kubernetes, and troubleshooting, I handled the routine investigation, command execution, and validation myself.

For the more complex issues, I used ChatGPT to explore possible root causes, validate my debugging approach, and improve the clarity of my findings and documentation. I cross-checked the suggestions against the project files, command outputs, and actual test results before accepting them.

The final submission reflects the changes I made and the results I verified. I am prepared to explain the troubleshooting process, root causes, fixes, and technical decisions during a live interview.
