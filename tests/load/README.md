# Load Tests

k6 load tests for CloudMart services running on EKS.

## Prerequisites

```bash
# Install k6
winget install k6
# or
choco install k6
```

## URL Configuration

**Never hardcode URLs.** Pass the target URL as an environment variable at runtime.

The base URL is the AWS ALB DNS name created by the ingress controller. Get it with:

```bash
kubectl get ingress cloudmart-ingress -n cloudmart-prod \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Set it as an environment variable before running any test:

```bash
# Windows PowerShell
$env:BASE_URL = "http://<your-alb-dns>.ap-south-1.elb.amazonaws.com"

# Bash
export BASE_URL="http://<your-alb-dns>.ap-south-1.elb.amazonaws.com"
```

## Running Tests

```bash
# Product service load test
k6 run --env BASE_URL=$env:BASE_URL tests/load/product-service.js

## Watching HPA During a Test

Open three terminals before starting the test:

```bash
# Terminal 1 — watch HPA decisions
kubectl get hpa product-service-hpa -n cloudmart-prod -w

# Terminal 2 — watch pods being created/terminated
kubectl get pods -n cloudmart-prod -l app=product-service -w

# Terminal 3 — live CPU/memory per pod
watch kubectl top pods -n cloudmart-prod -l app=product-service
```

Then run the test in a fourth terminal.

## Test Scripts

| Script | Purpose | Peak VUs | Duration |
|---|---|---|---|
| `product-service.js` | Ramp → sustain → ramp down | 200 | ~2 min |

## Expected HPA Behaviour

The product-service HPA ([`k8s/deployments/product-service.yaml`](../../k8s/deployments/product-service.yaml)) triggers when:
- CPU average > **60%** of the `100m` request → scales up
- Memory average > **80%** of the `128Mi` request → scales up
- Min replicas: **2**, Max replicas: **6**

Scale-down happens ~5 minutes after load drops (default cooldown).
