# CloudMart — Complete Technical Reference
> Generated from codebase at `c:\CloudMart`. Feed this document to an LLM to answer viva questions on the CloudMart cloud-native e-commerce platform.

---

## Table of Contents
1. [System Overview](#1-system-overview)
2. [End-to-End Request Flow](#2-end-to-end-request-flow)
3. [Microservices Architecture](#3-microservices-architecture)
4. [Kubernetes Configuration](#4-kubernetes-configuration)
5. [Autoscaling (HPA & Cluster Autoscaler)](#5-autoscaling)
6. [Terraform Infrastructure (IaC)](#6-terraform-infrastructure)
7. [Networking & VPC](#7-networking--vpc)
8. [Security Architecture](#8-security-architecture)
9. [Observability & Monitoring](#9-observability--monitoring)
10. [CI/CD Pipelines](#10-cicd-pipelines)
11. [Disaster Recovery](#11-disaster-recovery)
12. [Cost Architecture](#12-cost-architecture)
13. [AWS Resource Inventory](#13-aws-resource-inventory)

---

## 1. System Overview

**Project:** CloudMart — Cloud-native microservices e-commerce platform  
**University:** University of Moratuwa — IS 4630 Cloud Infrastructure Management  
**AWS Region:** `ap-south-1` (Mumbai)  
**AWS Account ID:** `145023091806`  
**Kubernetes:** EKS v1.32  

### Team Ownership Map

| Member | Domain |
|--------|--------|
| Ashan (214081P) | End-to-end flow, Autoscaling |
| Kavishka (214164A) | Infrastructure (Terraform), Cost Management |
| Nethma (214103M) | Networking (VPC), Disaster Recovery |
| Thakshaka (214006T) | Security (IAM/IRSA/NetworkPolicy), Observability |
| Raveesha (214143J) | CI/CD (GitHub Actions) |

---

## 2. End-to-End Request Flow

### 2.1 Browser → Product Catalogue (Full Path)

```
User types cloudmart.example.com
        │
        ▼
Route 53 DNS  →  resolves to ALB DNS name
        │
        ▼
AWS Application Load Balancer (ALB)
  - internet-facing, in public subnets 10.0.1.0/24 & 10.0.2.0/24
  - listens on HTTP:80
  - managed by AWS Load Balancer Controller (deployed via Helm in kube-system)
  - Ingress resource: k8s/ingress/frontend-ingress.yaml
        │
        ▼
EKS Worker Nodes (t3.medium, private subnets 10.0.11.0/24 & 10.0.12.0/24)
  - ALB routes to pod IP directly (target-type: ip)
        │
        ▼
frontend pod (Nginx, port 80, namespace: cloudmart-prod)
  - serves React SPA bundle
  - React Router handles client-side navigation
        │
        ▼ (browser makes API call)
frontend → product-service:8001  (ClusterIP Service)
  - Kubernetes DNS: product-service.cloudmart-prod.svc.cluster.local
  - product-service queries DynamoDB table: cloudmart-products
        │
        ▼
DynamoDB (ap-south-1) → returns product list → browser renders catalogue
```

### 2.2 API Call Routing — Inside vs Outside Cluster

**Frontend → Backend API calls stay INSIDE the cluster** after the initial page load.  
The browser, once it has the React SPA, makes XHR/fetch calls to `/api/products`, `/api/orders`, etc. These are proxied by the Nginx config inside the frontend container to `http://product-service:8001`, `http://order-service:8002` etc. — these are Kubernetes ClusterIP service names resolved via **kube-dns (CoreDNS)**, never leaving the VPC.

The ALB is only hit once per user session for the initial HTML/JS load and for any direct external API calls; all inter-service traffic stays in-cluster.

### 2.3 Service Discovery — How order-service Finds product-service

Kubernetes runs **CoreDNS** in the `kube-system` namespace. When a pod sends a request to `http://product-service:8001`, CoreDNS resolves `product-service` → the ClusterIP of the `product-service` Service object → kube-proxy routes to one of the backing pods.

The configmap sets:
```yaml
PRODUCT_SERVICE_URL: http://product-service:8001
ORDER_SERVICE_URL: http://order-service:8002
```

No hard-coded IPs — Kubernetes Service objects provide stable DNS names and VIPs regardless of pod churn.

### 2.4 How notification-service Learns of a New Order

`notification-service` has **no inbound HTTP traffic**. It uses **event-driven, pull-based messaging**:

1. `order-service` creates an order → publishes a JSON message to **SQS queue** `cloudmart-order-events`
2. `notification-service` runs a polling loop (every `NOTIFICATION_POLL_INTERVAL=5000ms`) calling SQS `ReceiveMessage`
3. On receiving a message, it calls **AWS SES** to send an order-confirmation email to the customer
4. It then calls `DeleteMessage` to remove the message from the queue

The SQS queue URL: `https://sqs.ap-south-1.amazonaws.com/145023091806/cloudmart-order-events`

### 2.5 What Happens if product-service Is Down During Checkout

There is **no explicit graceful degradation** configured in the current codebase. If `product-service` is completely unavailable:
- `order-service` calls `product-service` for stock validation — this call will fail with a connection error or timeout
- `order-service` returns an HTTP 5xx to the frontend
- The user sees an error; checkout fails

The system does NOT degrade gracefully (no circuit breaker, fallback catalogue, or cached inventory). The ALB and HPA ensure availability via multiple replicas — if one product-service pod crashes, traffic is rerouted to the remaining healthy pods within seconds via readiness probes.

### 2.6 Healthy kubectl get pods Output

```
kubectl get pods -n cloudmart-prod

NAME                                    READY   STATUS    RESTARTS   AGE
frontend-<hash>-<id>                    1/1     Running   0          2d
frontend-<hash>-<id>                    1/1     Running   0          2d
product-service-<hash>-<id>             1/1     Running   0          2d
product-service-<hash>-<id>             1/1     Running   0          2d
order-service-<hash>-<id>               1/1     Running   0          2d
order-service-<hash>-<id>               1/1     Running   0          2d
user-service-<hash>-<id>                1/1     Running   0          2d
user-service-<hash>-<id>                1/1     Running   0          2d
notification-service-<hash>-<id>        1/1     Running   0          2d
```

**Expected pod count: 9** (2 frontend + 2 product + 2 order + 2 user + 1 notification)

### 2.7 SQS Message Delivery & Duplicate Risk

SQS provides **at-least-once delivery** — not exactly-once.

**What happens if notification-service pod crashes mid-processing:**
1. The pod fetched the message (SQS hides it for 30 seconds — the **visibility timeout**)
2. Pod crashes before calling `DeleteMessage`
3. After 30 seconds, SQS makes the message visible again
4. Another (or restarted) notification-service pod receives it and processes it again
5. **Result: the customer MAY receive two order confirmation emails**

The DLQ (`cloudmart-order-events-dlq`) catches messages that fail more than 5 times (`maxReceiveCount=5`), preventing infinite retry loops. The system does NOT implement idempotency guards (e.g., checking a "notification already sent" flag in DynamoDB) in the current codebase.

---

## 3. Microservices Architecture

### 3.1 Service Inventory

| Service | Port | Runtime | Framework | Data Store |
|---------|------|---------|-----------|-----------|
| frontend | 80 | Node 20 → Nginx | React 18.3.1 | — (SSR-less SPA) |
| product-service | 8001 | Python 3.11 | Flask 3.0.3 + Gunicorn | DynamoDB (`cloudmart-products`) |
| order-service | 8002 | Node 20 | Express 4.19.2 | SQS (publishes) |
| user-service | 8003 | Python 3.11 | Flask 3.0.3 + Gunicorn + PyJWT + bcrypt + psycopg2 | RDS PostgreSQL 16 |
| notification-service | 8004 | Node 20 | Express 4.19.2 | SQS (consumes) + SES (sends email) |

### 3.2 Adapter Pattern — Multi-Cloud Portability

Every service uses environment-variable-driven adapter selection:

| Service | Variable | Values |
|---------|----------|--------|
| product-service | `STORE_BACKEND` | `memory` \| `dynamodb` \| `firestore` \| `cosmosdb` |
| order-service | `QUEUE_BACKEND` | `memory` \| `sqs` \| `pubsub` \| `servicebus` |
| user-service | `USER_DB_BACKEND` | `memory` \| `postgres` |
| notification-service | `QUEUE_BACKEND` + `EMAIL_BACKEND` | sqs + ses (prod), memory + console (local) |

Production values are set in `k8s/configmaps/configmap.yaml`.

### 3.3 Local Development (docker-compose.yml)

```yaml
Network: cloudmart (bridge)
Exposed ports:
  frontend:              3000 → 80
  product-service:       8001
  order-service:         8002
  user-service:          8003
  notification-service:  8004

Key env overrides for local dev:
  STORE_BACKEND=memory
  QUEUE_BACKEND=sqs        # still uses real SQS
  EMAIL_BACKEND=console    # emails print to stdout
  JWT_SECRET=cloudmart-dev-secret-change-in-production
```

### 3.4 Container Images (Dockerfiles)

All images use **multi-stage builds** and **non-root users**:

| Service | Base Image (build) | Base Image (runtime) | User | Health Check |
|---------|-------------------|---------------------|------|-------------|
| frontend | node:20-alpine | nginx:1.30-alpine | nginx | HTTP GET /health |
| product-service | python:3.11-slim | python:3.11-slim | appuser | HTTP GET /health |
| order-service | node:20-alpine | node:20-alpine | appuser | wget /health |
| user-service | python:3.11-slim | python:3.11-slim | appuser | HTTP GET /health |
| notification-service | node:20-alpine | node:20-alpine | appuser | wget /health |

Health check defaults: interval=30s, timeout=3s, start-period=5–10s, retries=3

---

## 4. Kubernetes Configuration

### 4.1 Namespaces

```yaml
# k8s/namespaces/namespace.yaml
cloudmart-prod      # production workloads
cloudmart-staging   # staging / pre-prod
```

### 4.2 Deployments — Resource Specifications

| Service | Replicas | CPU Request | CPU Limit | Mem Request | Mem Limit | Strategy |
|---------|---------|-------------|-----------|-------------|-----------|----------|
| frontend | 2 | 50m | 200m | 64Mi | 128Mi | RollingUpdate |
| product-service | 2 | 100m | 500m | 128Mi | 256Mi | RollingUpdate maxSurge=1 maxUnavailable=0 |
| order-service | 2 | 100m | 500m | 128Mi | 256Mi | RollingUpdate maxSurge=1 maxUnavailable=0 |
| user-service | 2 | 100m | 500m | 128Mi | 256Mi | RollingUpdate maxSurge=1 maxUnavailable=0 |
| notification-service | 1 | 50m | 200m | 64Mi | 128Mi | RollingUpdate |

**maxSurge: 1, maxUnavailable: 0 explained:**  
With 2 replicas:
1. Kubernetes creates 1 new pod (total now 3 — 2 old + 1 new)
2. Waits for new pod to pass readiness probe
3. Terminates 1 old pod (total 2 — 1 old + 1 new)
4. Repeats — at no point does available capacity drop below 2

### 4.3 ConfigMap (k8s/configmaps/configmap.yaml)

```yaml
AWS_REGION: ap-south-1
PRODUCT_STORE_BACKEND: dynamodb
PRODUCTS_TABLE_NAME: cloudmart-products
PRODUCT_SERVICE_URL: http://product-service:8001
ORDER_QUEUE_BACKEND: sqs
ORDER_EVENTS_QUEUE_URL: https://sqs.ap-south-1.amazonaws.com/145023091806/cloudmart-order-events
ORDER_SERVICE_URL: http://order-service:8002
NOTIFICATION_QUEUE_BACKEND: sqs
NOTIFICATION_EMAIL_BACKEND: ses
NOTIFICATION_POLL_INTERVAL: "5000"
SES_SENDER_EMAIL: rinduwara0@gmail.com
USER_DB_BACKEND: postgres
DB_HOST: cloudmart-user-db.cjc6cqeq0ser.ap-south-1.rds.amazonaws.com
DB_PORT: "5432"
DB_NAME: cloudmart_userr-db
DB_USER: cloudmartadmin
DB_SSLMODE: require
DB_SECRET_NAME: cloudmart/prod/user-service/db
JWT_SECRET_NAME: cloudmart/prod/user-service/jwt
```

### 4.4 Ingress (k8s/ingress/frontend-ingress.yaml)

```yaml
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
  alb.ingress.kubernetes.io/healthcheck-path: /health
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'

rules:
  - path: /
    backend: frontend:80
```

ALB is provisioned by the **AWS Load Balancer Controller** running in `kube-system`, which watches Ingress objects and creates/updates real ALBs in AWS.

### 4.5 Service Accounts & IRSA

```yaml
# Each service has its own ServiceAccount with annotation:
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::145023091806:role/cloudmart-<service>-role

Deployed in: cloudmart-prod AND cloudmart-staging
```

| ServiceAccount | IAM Role |
|---------------|---------|
| product-service-sa | cloudmart-product-service-role |
| order-service-sa | cloudmart-order-service-role |
| user-service-sa | cloudmart-user-service-role |
| notification-service-sa | cloudmart-notification-service-role |

### 4.6 Network Policies

#### Default Deny (k8s/network-policies/default-deny.yaml)
```yaml
# Blocks ALL ingress and egress for every pod in the namespace by default
podSelector: {}
policyTypes: [Ingress, Egress]
# No ingress/egress rules = deny all
```

#### Allow Frontend → Backends
```yaml
# allow-frontend-to-backend.yaml
podSelector:
  matchLabels: app: frontend
egress:
  - to:
    - podSelector: {matchLabels: {app: product-service}}
    ports: [{port: 8001}]
  - to:
    - podSelector: {matchLabels: {app: order-service}}
    ports: [{port: 8002}]
  - to:
    - podSelector: {matchLabels: {app: user-service}}
    ports: [{port: 8003}]
```

#### Allow order-service → product-service
```yaml
# allow-order-to-product.yaml
podSelector:
  matchLabels: app: order-service
egress:
  - to:
    - podSelector: {matchLabels: {app: product-service}}
    ports: [{port: 8001}]
```

#### Allow Egress to AWS Services (HTTPS:443)
```yaml
# allow-egress-to-aws-services.yaml
# Applied to: product-service, order-service, notification-service, user-service
egress:
  - ports: [{port: 443, protocol: TCP}]
    # Allows outbound to DynamoDB, SQS, SES, Secrets Manager, ECR etc.
```

#### Allow user-service → RDS
```yaml
# allow-user-to-rds.yaml
podSelector:
  matchLabels: app: user-service
egress:
  - to:
    - ipBlock: {cidr: 10.0.0.0/16}
    ports: [{port: 5432}]
```

**What NetworkPolicy prevents user-service from talking directly to order-service:**  
The default-deny policy blocks all traffic. The only egress policies for user-service allow port 443 (AWS services) and port 5432 (RDS). There is no rule permitting egress from user-service to order-service on port 8002, so that traffic is dropped.

---

## 5. Autoscaling

### 5.1 HPA Configuration

```yaml
# product-service HPA (k8s/deployments/product-service.yaml or separate HPA)
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: product-service-hpa
  namespace: cloudmart-prod
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: product-service
  minReplicas: 2
  maxReplicas: 6
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80

# order-service HPA: minReplicas=2, maxReplicas=6, CPU 60%
```

### 5.2 HPA vs Cluster Autoscaler — Difference & Order of Operations

| Aspect | HPA (Horizontal Pod Autoscaler) | Cluster Autoscaler |
|--------|--------------------------------|-------------------|
| What it scales | Number of pod replicas | Number of EC2 nodes |
| Trigger | CPU/memory utilization % | Pods stuck in `Pending` state |
| Speed | 15–60 seconds | 3–5 minutes |
| Scope | Single deployment | Entire node group |
| Config location | HPA object in k8s manifests | EKS managed node group (min=2, max=3) |

**Traffic spike sequence:**
1. CPU on existing product-service pods rises above 60%
2. **HPA triggers first** (within ~30–60s) — adds new pod replicas
3. If new pods cannot be scheduled (no node capacity), they enter `Pending`
4. **Cluster Autoscaler triggers** (within 3–5 min) — provisions a new t3.medium node
5. Pods are scheduled on the new node

### 5.3 Why 60% CPU Target?

60% is chosen as a **buffer**. If target were 80%, a sudden spike could cause pods to hit 100% CPU before the HPA has time to scale (15–30 second scrape interval + time to start new pods). At 60%, there's a 40% headroom to absorb burst traffic while new pods are warming up.

### 5.4 What HPA Actually Reads — Metrics Source

The HPA reads metrics from the **Kubernetes Metrics Server** (or in EKS, via **CloudWatch Container Insights** + the metrics-server add-on). The flow:
- `kubelet` on each node collects CPU/memory stats via cAdvisor
- `metrics-server` aggregates these and exposes them via the Kubernetes `metrics.k8s.io` API
- HPA controller queries this API every 15 seconds

In EKS with Container Insights, per-pod CPU metrics flow: pod cAdvisor → CloudWatch agent (DaemonSet) → CloudWatch → visible in console.

### 5.5 Pod Pending + Node Full Scenario

**With maxSurge=1, 2 replicas, HPA wants 4 pods, 3 nodes all full:**

1. HPA requests scale from 2 → 4 pods
2. 2 new pods created, both enter `Pending` (no node capacity)
3. Cluster Autoscaler sees `Pending` pods after ~10s
4. CA checks: can adding a node make these pods schedulable? Yes.
5. CA calls EC2 API to launch a new node (node group max=3 allows it)
6. New node joins cluster in ~3–5 min
7. Pods scheduled, become `Running`

**If node group max (3 nodes) is already reached and HPA wants 6 pods:**
- HPA can request 6 pods, but only pods that fit on 3 nodes will be scheduled
- Remaining pods stay `Pending` indefinitely
- Cluster Autoscaler will NOT add a 4th node (max=3 is a hard cap)
- This is a capacity ceiling — the system is overloaded and requests will be queued/dropped

### 5.6 How to Test Autoscaling

```bash
# Install load testing tool
kubectl run load-generator --image=busybox --restart=Never -n cloudmart-prod -- \
  /bin/sh -c "while true; do wget -q -O- http://product-service:8001/products; done"

# Or use hey / k6
kubectl run load-test --image=grafana/k6 -n cloudmart-prod -- \
  k6 run -u 50 -d 2m /scripts/load.js

# Watch HPA respond
kubectl get hpa -n cloudmart-prod -w

# Watch pods scale
kubectl get pods -n cloudmart-prod -w

# Watch nodes
kubectl get nodes -w
```

---

## 6. Terraform Infrastructure

### 6.1 State Management

```hcl
# infra/provider.tf
backend "s3" {
  bucket         = "terraform-cloudmart-state-bucket"
  key            = "cloudmart/shared/terraform.tfstate"
  region         = "ap-south-1"
  dynamodb_table = "terraform-cloudmart-state-locks"
  encrypt        = true
}
```

**DynamoDB lock table (`terraform-cloudmart-state-locks`) purpose:**  
Prevents simultaneous `terraform apply` runs. When apply starts, Terraform writes a lock item to the DynamoDB table. A second concurrent apply attempt will read this lock and abort with "Error: Error locking state: Error acquiring the state lock." Without it, two simultaneous applies could corrupt the state file (race condition on the S3 object).

**Backend bootstrap (infra/backend/main.tf):**
- S3 bucket: versioning enabled, public access blocked, AES256 encryption
- DynamoDB lock table: PAY_PER_REQUEST billing

### 6.2 Module Structure

```
infra/
├── main.tf            # Root module — calls all child modules
├── variables.tf       # Input variable declarations
├── outputs.tf         # Output values (VPC IDs, endpoints, etc.)
├── provider.tf        # AWS provider config + S3 backend
├── backend/
│   └── main.tf        # Bootstrap: S3 bucket + DynamoDB lock table
└── modules/
    ├── vpc/           # VPC, subnets, IGW, NAT, route tables
    ├── security-groups/ # ALB, EKS, RDS, bastion, VPC endpoint SGs
    ├── eks/           # EKS cluster, node group, OIDC, IAM roles, launch template
    ├── kms/           # Customer managed KMS key
    ├── rds/           # PostgreSQL RDS instance + subnet group + parameter group
    ├── dynamodb/      # Products table + GSI
    ├── sqs/           # Order events queue + DLQ
    ├── secrets-manager/ # DB secret, JWT secret, notification config
    ├── ses/           # SES email identity verification
    ├── ecr/           # Container registries (one per service)
    ├── iam/           # IRSA roles and policies per service
    └── alb/           # IAM role for AWS Load Balancer Controller
```

**To add a DR cluster in a second region:** Touch `modules/eks`, `modules/vpc`, `modules/rds`, and `modules/dynamodb` (add global tables). Add a new provider block for the DR region in `provider.tf`. Add new module calls in `main.tf` passing DR-specific variables.

### 6.3 Staging vs Production Differentiation

Terraform uses the `environment` variable (`shared` by default). In CI/CD or manual workflows, separate `.tfvars` files or workspace-specific variable files control environment-specific values:
- `staging.tfvars`: smaller instance sizes, single-AZ RDS, lower node counts
- `production.tfvars`: t3.medium nodes, Multi-AZ optional, larger storage

Kubernetes namespaces (`cloudmart-staging` vs `cloudmart-prod`) separate runtime environments.

### 6.4 Manual AWS Console Change → terraform apply Behavior

If someone manually edits an EKS security group in the console:
1. `terraform plan` will detect the drift: shows `~ update in-place` with the console-made value vs. Terraform-declared value
2. `terraform apply` will **overwrite** the manual change to match the declared configuration
3. The console change is lost — Terraform is authoritative

**This is why `terraform plan` output is critical to review** before apply: it shows exactly what will be created (`+`), modified (`~`), or destroyed (`-`). Reviewing prevents accidental destructive changes.

### 6.5 Key Variable Values

```hcl
# Networking
vpc_cidr              = "10.0.0.0/16"
availability_zones    = ["ap-south-1a", "ap-south-1b"]
public_subnets        = ["10.0.1.0/24", "10.0.2.0/24"]
private_app_subnets   = ["10.0.11.0/24", "10.0.12.0/24"]
private_data_subnets  = ["10.0.21.0/24", "10.0.22.0/24"]
single_nat_gateway    = true

# EKS
kubernetes_version    = "1.32"
node_instance_types   = ["t3.medium"]
capacity_type         = "ON_DEMAND"
desired_nodes         = 2
min_nodes             = 2
max_nodes             = 3
node_disk_size        = 30  # GiB

# RDS
db_instance_class     = "db.t4g.micro"
db_engine             = "postgres"
db_engine_version     = "16"
db_storage            = 20   # GB
db_max_storage        = 30   # GB
db_backup_retention   = 7    # days
db_multi_az           = false

# DynamoDB
dynamodb_billing_mode = "PAY_PER_REQUEST"

# SQS
sqs_visibility_timeout     = 30
sqs_message_retention      = 345600  # 4 days
sqs_dlq_message_retention  = 1209600 # 14 days
sqs_max_receive_count      = 5
```

---

## 7. Networking & VPC

### 7.1 VPC CIDR Breakdown

```
VPC: 10.0.0.0/16  (65,536 addresses)

PUBLIC SUBNETS (ALB lives here):
  10.0.1.0/24  → ap-south-1a  (254 usable)
  10.0.2.0/24  → ap-south-1b  (254 usable)

PRIVATE APP SUBNETS (EKS worker nodes live here):
  10.0.11.0/24 → ap-south-1a  (254 usable)
  10.0.12.0/24 → ap-south-1b  (254 usable)

PRIVATE DATA SUBNETS (RDS lives here):
  10.0.21.0/24 → ap-south-1a  ← RDS primary here
  10.0.22.0/24 → ap-south-1b  (254 usable)
```

**RDS in ap-south-1a** is in subnet `10.0.21.0/24`.

### 7.2 What Lives Where

| Layer | Resources | Subnet Type |
|-------|-----------|-------------|
| Public | ALB, NAT Gateway, Internet Gateway | public (10.0.1.x, 10.0.2.x) |
| Private App | EKS worker nodes (t3.medium), pods | private-app (10.0.11.x, 10.0.12.x) |
| Private Data | RDS PostgreSQL, (DynamoDB is AWS-managed, no subnet) | private-data (10.0.21.x, 10.0.22.x) |

### 7.3 Why Public AND Private Subnets?

- **Public subnets:** Resources that need a public IP or direct internet routing (ALB, NAT GW itself)
- **Private subnets:** Resources that should NEVER be directly internet-accessible (worker nodes, database). They reach the internet outbound-only through the NAT Gateway.

Security principle: **EKS nodes and RDS never have public IPs** — no attack surface.

### 7.4 NAT Gateway — Purpose & Risk

**Purpose:** Allows EKS worker nodes (in private subnets) to initiate outbound internet connections:
- Pull container images from ECR
- Call AWS APIs (DynamoDB, SQS, SES, Secrets Manager)
- System updates

**Without the NAT Gateway:** Worker nodes cannot reach ECR → pods cannot start (image pull errors).

**Single NAT Gateway risk (cost optimization in current config):**
- There is ONE NAT Gateway in (e.g.) ap-south-1a
- If ap-south-1a AZ fails, worker nodes in ap-south-1b lose outbound internet access
- This means **all** private subnet resources lose outbound connectivity if one AZ fails
- Justification: for a university project, cost savings outweigh HA requirements
- At production traffic levels or with SLA requirements, add a NAT GW per AZ

### 7.5 VPC Private Endpoints

The following AWS services have **VPC Interface Endpoints** (PrivateLink):
- ECR (image pulls)
- CloudWatch (log shipping)
- Secrets Manager (secret retrieval)

**Without private endpoints:** Traffic to `ecr.ap-south-1.amazonaws.com` would route through the NAT Gateway → internet → back to AWS. This adds latency and NAT bandwidth cost.

**With private endpoints:** Traffic stays entirely within the AWS network via PrivateLink — faster, cheaper, and never touches the internet.

### 7.6 Security Group vs NetworkPolicy — Key Difference

| | Security Group | Kubernetes NetworkPolicy |
|-|----------------|--------------------------|
| Layer | AWS VPC level (EC2/ENI) | Kubernetes pod level |
| Enforcement | AWS hypervisor (hardware) | CNI plugin (e.g., VPC-CNI with Calico) |
| Scope | Between EC2 instances/ENIs | Between pods (even on same node) |
| Granularity | IP, port, protocol | Pod labels, namespace, port |
| Awareness | No concept of pods/services | Label-selector based |

You need **both**: Security Groups protect the node boundary (EKS nodes from external); NetworkPolicies protect pod-to-pod traffic within the cluster. A Security Group alone cannot restrict traffic between two pods on the same node.

### 7.7 Verifying RDS Is NOT Internet-Reachable

```bash
# Method 1: Check the RDS Security Group
aws ec2 describe-security-groups --group-ids <rds-sg-id> --region ap-south-1
# Verify: inbound rules should show ONLY port 5432 from EKS node SG, NOT 0.0.0.0/0

# Method 2: Check RDS instance attribute
aws rds describe-db-instances --db-instance-identifier cloudmart-user-db --region ap-south-1
# Verify: "PubliclyAccessible": false

# Method 3: Live test from outside VPC
psql -h cloudmart-user-db.cjc6cqeq0ser.ap-south-1.rds.amazonaws.com -p 5432 -U cloudmartadmin
# Should time out — no route from internet to private subnet
```

---

## 8. Security Architecture

### 8.1 IRSA (IAM Roles for Service Accounts) — Plain Terms

**IRSA = Workload Identity for Kubernetes on AWS**

Without IRSA, to give a pod AWS permissions you'd need to:
- Store `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` in environment variables or ConfigMaps
- These are long-lived static credentials — if leaked, they grant persistent access

**With IRSA:**
1. EKS creates an **OIDC provider** (endpoint: the cluster's OIDC issuer URL)
2. Each ServiceAccount is annotated with an IAM role ARN
3. When a pod starts, the EKS Pod Identity webhook injects temporary credentials from AWS STS into the pod via a projected volume
4. The pod exchanges these short-lived OIDC tokens for temporary AWS credentials (valid 1 hour, auto-refreshed)
5. IAM trust policy restricts: ONLY pods in namespace `cloudmart-prod` using ServiceAccount `notification-service-sa` can assume the role

**Why better than env vars:**
- Credentials are **temporary** (1h TTL, auto-rotated)
- **No secrets to store** — no risk of leaking static keys
- **Fine-grained scoping** — role trust policy binds to exact namespace + ServiceAccount
- **Auditable** — CloudTrail shows which pod assumed which role

### 8.2 Notification-Service IAM Permissions (Exact)

```json
{
  "Permissions granted to cloudmart-notification-service-role": {
    "SQS": [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes"
    ],
    "SES": [
      "ses:SendEmail",
      "ses:SendRawEmail"
      // Resource: arn:aws:ses:ap-south-1:145023091806:identity/rinduwara0@gmail.com
    ],
    "KMS": [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey"
    ]
  }
}
```

**Why notification-service CANNOT read DynamoDB:**  
The IAM policy only lists SQS, SES, and KMS actions. There is no `dynamodb:*` statement. AWS IAM is **default deny** — if a permission isn't explicitly granted, it's denied. The notification-service has no business reason to access DynamoDB (it only processes order events and sends emails).

### 8.3 IMDSv2 — What and Why

**IMDS (Instance Metadata Service)** is an HTTP endpoint at `169.254.169.254` that EC2 instances use to retrieve instance metadata and IAM credentials.

**IMDSv1 vulnerability:** Any process on the node (including a compromised pod) could call `curl http://169.254.169.254/latest/meta-data/iam/security-credentials/` and steal the node's IAM role credentials — this was the **Capital One breach** attack vector (SSRF to IMDS).

**IMDSv2 enforcement (in EKS launch template):**
```hcl
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required"   # Forces IMDSv2
  http_put_response_hop_limit = 2            # Allows pods to reach IMDS (1 extra hop for container namespace)
}
```

With `http_tokens = required`, the IMDS requires a session token obtained via a PUT request. A pod doing SSRF via the application layer cannot make the preliminary PUT request needed for IMDSv2 (most SSRF vulnerabilities are limited to GET).

### 8.4 What an Attacker Can Access From Inside a Product-Service Pod

**CAN access:**
- DynamoDB `cloudmart-products` table (via IRSA credentials — the pod is supposed to have this)
- Kubernetes Secrets and ConfigMaps mounted in the pod
- The internal cluster network — within NetworkPolicy allowances (can reach from product-service side: nothing new, but could be called by other pods)
- Environment variables in the current pod

**CANNOT access:**
- SQS queue (no SQS permission on product-service-role)
- RDS database (no DB credentials, not allowed through NetworkPolicy or Security Groups)
- Other pods' secrets
- AWS account root credentials
- Secrets Manager (no permission on product-service-role)
- User service data
- Other IAM roles (cannot escalate — trust policies are namespace+SA scoped)

### 8.5 KMS Key — Management & Deletion Risk

**Key management:**
- Customer Managed Key (CMK) — CloudMart owns and manages it
- Alias: `alias/cloudmart-kms-{version}`
- Auto-rotation: **enabled** (AWS rotates the backing key material annually)
- Deletion window: **7 days** (minimum AWS allows)
- Managed by: the Terraform `cloudmart-eks` IAM role and root account

**If the KMS key is accidentally deleted:**
1. AWS schedules deletion (immediate effect: key is disabled; deletion after 7-day waiting period)
2. **Immediately:** All KMS encrypt/decrypt operations fail
3. RDS cannot decrypt storage → database becomes inaccessible
4. DynamoDB items encrypted with this key → unreadable
5. SQS messages → undecryptable
6. Secrets Manager secrets → inaccessible → pods crash (cannot fetch DB password)
7. EKS etcd secrets → unreadable → cluster control plane issues
8. **Recovery:** Cancel deletion within the 7-day window using AWS Console or CLI (`aws kms cancel-key-deletion`)
9. If deletion window expires: **data is permanently unrecoverable** — no backup of CMK material exists outside AWS KMS

### 8.6 Trivy Scan in CI/CD — CRITICAL Findings

A CRITICAL Trivy finding = a CVE with CVSS score ≥ 9.0 in the container image.

**Example CRITICAL in `node:20-alpine`:**
- `CVE-2024-XXXX` in `openssl` — remote code execution via TLS parsing
- `CVE-2023-44487` (HTTP/2 Rapid Reset DoS in Go packages bundled with node)

**Pipeline behavior on CRITICAL finding:**
- The Trivy scan step runs AFTER `docker build` but BEFORE `docker push`
- If CRITICAL found: the workflow step **exits non-zero** → GitHub Actions marks the job as failed
- **Nothing is pushed to ECR** (the push step never executes)
- The deployment step also never runs
- Other independent service pipelines are NOT affected (each service has its own workflow)

### 8.7 Non-Root Container Enforcement

**In Dockerfile:** `USER appuser` — the container process starts as a non-root user.

**How Kubernetes knows if running as root:** The kubelet reads the container's UID from the OCI runtime. If UID=0, it's root.

**Enforce at cluster level via PodSecurity Admission (PSA):**
```yaml
# Apply to namespace:
apiVersion: v1
kind: Namespace
metadata:
  labels:
    pod-security.kubernetes.io/enforce: restricted
    # restricted profile requires: non-root, no privilege escalation, read-only root FS
```

Or using a `PodSecurityContext` in every deployment:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
```

The current project enforces non-root via Dockerfiles. Cluster-level PSA enforcement is a recommended hardening step.

---

## 9. Observability & Monitoring

### 9.1 Log Collection Path — stdout → CloudWatch

```
Pod process writes to stdout/stderr
        │
        ▼
Container runtime (containerd) writes to node filesystem
  /var/log/containers/<pod-name>.log
        │
        ▼
CloudWatch Agent (DaemonSet on each node)
  - runs as a pod on every worker node
  - reads /var/log/containers/
  - IAM permission: CloudWatchAgentServerPolicy (granted to EKS node role)
        │
        ▼
CloudWatch Log Group: /aws/eks/cloudmart-eks/containers
  or per-service: /cloudmart/prod/<service-name>
        │
        ▼
CloudWatch Logs Insights for querying
```

Node IAM role has `CloudWatchAgentServerPolicy` — this is why the EKS node group IAM role includes this policy attachment.

### 9.2 Liveness vs Readiness Probes

| | Liveness Probe | Readiness Probe |
|-|---------------|----------------|
| **Failure action** | Kubernetes **restarts** the container | Kubernetes **removes pod from Service endpoints** (no traffic) |
| **Purpose** | Detect stuck/deadlocked processes | Detect pod not yet ready to serve traffic |
| **On failure** | SIGTERM → SIGKILL → new container | Pod stays running but gets no requests |

**Scenario — fail liveness but pass readiness (or vice versa):**

*Pass readiness, fail liveness:*  
A pod serving requests normally but a background goroutine is deadlocked. The `/health` endpoint still responds (readiness passes), but after 3 failed liveness probes (e.g., a deeper `/healthz` endpoint checks internal state), Kubernetes restarts the pod.

*Pass liveness, fail readiness:*  
During startup, a service is alive (process is running, responds to simple ping) but hasn't finished loading its configuration from Secrets Manager yet. Liveness passes (process is up), readiness fails (not ready to serve traffic) → Kubernetes holds traffic away until initialization completes. This is the **normal startup behavior** for all CloudMart services.

### 9.3 CloudWatch Alarm for product-service Error Rate

```json
{
  "AlarmName": "ProductService-ErrorRate-High",
  "MetricName": "5xxErrorRate",
  "Namespace": "AWS/ApplicationELB",
  "Dimensions": [
    {"Name": "TargetGroup", "Value": "targetgroup/product-service-tg/..."},
    {"Name": "LoadBalancer", "Value": "app/cloudmart-alb/..."}
  ],
  "Statistic": "Average",
  "Period": 300,
  "EvaluationPeriods": 1,
  "Threshold": 5.0,
  "ComparisonOperator": "GreaterThanThreshold",
  "TreatMissingData": "notBreaching"
}
```

Or for application-level errors logged to CloudWatch Logs:
- **Metric filter** on log group `/cloudmart/prod/product-service`
- Pattern: `ERROR` or `HTTP 5`
- Custom metric: `ProductService/ErrorCount`
- Alarm: `Sum` over 300s > threshold corresponding to 5% of request rate

### 9.4 Debugging HTTP 500s — Step-by-Step CloudWatch Investigation

1. **Open CloudWatch Log Groups** → `/cloudmart/prod/product-service`
2. **Logs Insights query:**
   ```sql
   fields @timestamp, @message
   | filter @message like /ERROR/ or @message like /500/
   | sort @timestamp desc
   | limit 50
   ```
3. Look for: exception stack traces, specific DynamoDB errors (throttling? item not found?), connection timeouts
4. **Cross-reference** with DynamoDB CloudWatch metrics: `ThrottledRequests`, `SystemErrors`
5. If DB-related: check `cloudmart-products` table → CloudWatch → `ConsumedReadCapacityUnits`
6. Check pod logs directly: `kubectl logs -n cloudmart-prod deployment/product-service --previous`
7. Check HPA: `kubectl describe hpa product-service-hpa -n cloudmart-prod` — is it scaling?

### 9.5 Per-Pod CPU Metrics Into CloudWatch from EKS

**Method:** AWS CloudWatch Container Insights

1. Enable Container Insights on the EKS cluster
2. Deploy the CloudWatch Agent as a **DaemonSet** (one pod per node)
3. The agent uses the Kubernetes API + cAdvisor to collect per-pod CPU/memory
4. Metrics published to CloudWatch namespace: `ContainerInsights`
5. Metric: `pod_cpu_utilization` with dimension `PodName`

Alternative: Prometheus + CloudWatch Prometheus Remote Write (pushes Prometheus metrics to CloudWatch as custom metrics).

---

## 10. CI/CD Pipelines

### 10.1 Workflow Files

```
.github/workflows/
├── product-service-ci.yml
├── order-service-ci.yml
├── user-service-ci.yml
├── notification-service-ci.yml
└── frontend-service-ci.yml
```

Each workflow is **independent** — a CRITICAL vulnerability in product-service does NOT block order-service deployment.

### 10.2 Full Pipeline on git push to develop

```
git push origin develop
        │
        ▼
GitHub Actions triggers workflow (on: push: branches: [develop, main])
        │
        ▼
Job 1: lint-test
  - Checkout code
  - Setup runtime (Python 3.11 or Node 20)
  - Install dependencies (pip install / npm ci)
  - Run linter (flake8 / eslint)
  - Run tests (unittest / jest --coverage)
        │
        ▼
Job 2: validate-k8s (parallel with lint-test OR sequential)
  - Download kubeconform v1.32.0
  - kubeconform -strict -ignore-missing-schemas ./k8s/
        │
        ▼
Job 3: build-scan-push
  - Configure AWS credentials (AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY from GitHub Secrets)
  - Login to ECR: aws-actions/amazon-ecr-login
  - Docker buildx build --platform linux/amd64
  - Tag image: {ecr_registry}/cloudmart/{service}:{GIT_SHA}
  - Trivy scan (CRITICAL severity only, ignore-unfixed)
    → If CRITICAL found: FAIL. Nothing pushed.
  - docker push to ECR
        │
        ▼
Job 4: deploy-staging (develop branch only, automatic)
  - aws eks update-kubeconfig --name cloudmart-eks
  - sed -i "s|image: .*|image: {registry}/{service}:{GIT_SHA}|" k8s/deployments/{service}.yaml
  - kubectl apply -f k8s/ -n cloudmart-staging
  - kubectl rollout status deployment/{service} -n cloudmart-staging
  - Sleep 60s (Argo CD sync time)
  - Smoke test: curl http://{service-endpoint}/health → expect HTTP 200
```

**For main branch:** Same pipeline but deploy-production job requires **GitHub Environment approval** (manual gate).

### 10.3 Image Tagging — Git SHA vs latest

**Why SHA tagging, not `latest`:**
- `latest` is mutable — two different images can have the same tag, making rollbacks ambiguous
- With SHA tagging (`image:abc1234`), every image is **immutable and uniquely identifiable**
- You can always trace exactly which code commit is running in production
- Rollback is deterministic: just set the deployment to the previous SHA

### 10.4 kubeconform — What It Catches vs YAML Linter

| Tool | What it catches |
|------|----------------|
| YAML linter (e.g., yamllint) | Syntax errors, indentation, trailing spaces |
| kubeconform | Schema validation — wrong field names, incorrect types, missing required fields, using fields from the wrong API version |

**Example kubeconform catches, YAML linter misses:**
```yaml
# This is valid YAML but invalid Kubernetes:
apiVersion: apps/v1
kind: Deployment
spec:
  replicas: "two"   # ← should be integer, not string
  template:
    spec:
      containers:
      - name: app
        ressources:  # ← typo: "ressources" instead of "resources"
          limits: {cpu: "500m"}
```
kubeconform validates against the Kubernetes JSON Schema for v1.32 — catches API deprecations, wrong field types, missing required fields.

### 10.5 Rolling Update with maxSurge=1, maxUnavailable=0 — 2 Replicas

Starting state: 2 pods running old version (v1)
```
Step 1: Create 1 new pod (v2) → 3 pods total (2×v1 + 1×v2)
Step 2: Wait for v2 pod to pass readiness probe
Step 3: Terminate 1 v1 pod → 2 pods (1×v1 + 1×v2)
Step 4: Create 1 new pod (v2) → 3 pods total (1×v1 + 2×v2)
Step 5: Wait for new v2 pod readiness
Step 6: Terminate last v1 pod → 2 pods (2×v2)
Done.
```

At no point are there fewer than 2 ready pods — zero downtime.

### 10.6 EKS Authentication in GitHub Actions

```yaml
# In workflow:
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
    aws-region: ap-south-1

- name: Update kubeconfig
  run: aws eks update-kubeconfig --name cloudmart-eks --region ap-south-1
```

The IAM user whose credentials are in GitHub Secrets must have:
- `eks:DescribeCluster` (for update-kubeconfig)
- Entry in EKS `aws-auth` ConfigMap (or EKS access entry) mapping to a Kubernetes RBAC role with deployment permissions

### 10.7 Rollback Procedure

```bash
# Check rollout status
kubectl rollout status deployment/product-service -n cloudmart-prod

# If stuck/unhealthy, roll back to previous revision
kubectl rollout undo deployment/product-service -n cloudmart-prod

# Or roll back to specific revision
kubectl rollout undo deployment/product-service -n cloudmart-prod --to-revision=3

# Verify rollback
kubectl rollout status deployment/product-service -n cloudmart-prod
kubectl get pods -n cloudmart-prod
```

### 10.8 Where to Add a Manual Approval Gate

In GitHub Actions, a manual gate is implemented using **GitHub Environments** with required reviewers:

```yaml
jobs:
  deploy-production:
    environment: production   # ← This triggers the manual gate
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        run: kubectl apply ...
```

In GitHub repo Settings → Environments → `production` → Required reviewers: add team leads.  

The job will **pause** after the build/scan/push job and wait for a human to click "Approve" in GitHub Actions UI before running the production kubectl apply.

---

## 11. Disaster Recovery

### 11.1 RTO and RPO

| Metric | Target | Justification |
|--------|--------|---------------|
| RTO (Recovery Time Objective) | ~4 hours | Time to rebuild EKS cluster from Terraform + redeploy apps |
| RPO (Recovery Point Objective) | ~1 hour | RDS automated backups every 1 hour |

Business reason: An e-commerce platform losing 1 hour of order data is acceptable for a university demo; a production SLA would demand RPO < 5 min (requiring RDS read replicas with near-real-time replication).

### 11.2 RDS Point-in-Time Restore Steps

**Restore to 3 hours ago in a test instance:**
```bash
# 1. Calculate the restore time (3 hours ago)
RESTORE_TIME=$(date -u -d "3 hours ago" +"%Y-%m-%dT%H:%M:%SZ")

# 2. Initiate restore to a NEW instance (cannot restore in-place)
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier cloudmart-user-db \
  --target-db-instance-identifier cloudmart-user-db-restored-test \
  --restore-time $RESTORE_TIME \
  --db-instance-class db.t4g.micro \
  --no-multi-az \
  --region ap-south-1

# 3. Wait for instance to become available
aws rds wait db-instance-available \
  --db-instance-identifier cloudmart-user-db-restored-test

# 4. Connect and verify data
psql -h <new-endpoint> -U cloudmartadmin -d cloudmart_users

# 5. If valid, update DB_HOST in ConfigMap + rolling restart user-service
#    (or swap DNS/endpoint reference)
```

Backup retention = 7 days means you can restore to any second within the past 7 days.

### 11.3 Full Region Failure Recovery Sequence

**Scenario: ap-south-1 completely unavailable**

1. **Detect outage** via Route 53 health checks → primary endpoint fails
2. **Route 53 DNS failover** activates → traffic redirected to DR region (e.g., ap-southeast-1)
3. **Retrieve Terraform state** from S3 cross-region replica in DR region
4. **Run Terraform** in DR region (pre-prepared DR configuration):
   ```bash
   terraform workspace select dr
   terraform apply -var-file=dr.tfvars
   ```
5. **Deploy EKS cluster** in DR region (VPC, subnets, node groups)
6. **Restore RDS** from latest automated backup (cross-region backup copy needed — currently not configured, would need `aws_db_instance.backup_retention` + cross-region copy)
7. **DynamoDB Global Tables** (if configured) → instantly available in DR region
8. **Push container images** to DR region ECR (or use cross-region ECR replication)
9. **Deploy Kubernetes manifests** → services come up
10. **Verify smoke tests** → confirm /health endpoints return 200
11. **Update Route 53** to point to DR ALB (or health check failover handles this automatically)

### 11.4 Route 53 DNS Failover — How It Detects Primary Failure

1. Route 53 **health checks** continuously poll the primary ALB endpoint (e.g., `GET /health` on the frontend service) from multiple AWS edge locations
2. If the health check returns non-2xx or times out for N consecutive checks → marks endpoint UNHEALTHY
3. Route 53 **automatically switches** the DNS record to the DR endpoint (failover routing policy)
4. TTL is low (e.g., 60s) so clients pick up the new IP quickly

### 11.5 Idempotent SQS Message Handling

**What "idempotent" means here:**  
Processing the same SQS message twice produces the same result as processing it once.

**Why it matters for notification-service:**  
SQS guarantees at-least-once delivery. If a pod crashes after receiving but before deleting a message, the message becomes visible again and gets reprocessed → duplicate email.

**Idempotency implementation (NOT in current codebase, but the answer):**
```python
# Before sending email, check a "sent" flag
order_id = message["orderId"]
already_sent = dynamodb.get_item(
    TableName="cloudmart-notifications-sent",
    Key={"orderId": {"S": order_id}}
)
if already_sent.get("Item"):
    # Already processed — skip, just delete from SQS
    sqs.delete_message(...)
    return
    
# Not yet sent — send email, then record
ses.send_email(...)
dynamodb.put_item(TableName="cloudmart-notifications-sent", 
                  Item={"orderId": {"S": order_id}, "sentAt": {"S": now}})
sqs.delete_message(...)
```

### 11.6 Terraform Apply in DR Region with S3 Unavailable

**S3 cross-region replication** copies the state file to a bucket in the DR region. If primary S3 (`ap-south-1`) is unavailable but the replica in DR region (`ap-southeast-1`) is available:

1. Update `provider.tf` backend bucket to the DR region's replica bucket
2. Run `terraform init -reconfigure` to point to DR state
3. `terraform apply` proceeds using DR state

**Without cross-region replication:** The state file is unavailable → `terraform apply` fails with "Error loading state". This is why cross-region replication of the S3 state bucket is critical for DR.

---

## 12. Cost Architecture

### 12.1 Monthly Cost Breakdown (~$196.69 estimate)

| Service | Monthly Cost | Notes |
|---------|-------------|-------|
| EKS Control Plane | ~$73.00 | $0.10/hour × 730h |
| EC2 Worker Nodes (2× t3.medium) | ~$60.00 | $0.0416/hr × 2 × 730h |
| RDS db.t4g.micro | ~$12.00 | PostgreSQL, single-AZ |
| NAT Gateway | ~$32.00 | $0.045/hr + data processing |
| ALB | ~$8.00 | LCU-based pricing |
| ECR Storage | ~$1.00 | ~5 images × 5 repos |
| DynamoDB | ~$0 | PAY_PER_REQUEST, low traffic |
| SQS | ~$0 | First 1M requests/month free |
| SES | ~$0 | First 62K emails/month free |
| CloudWatch | ~$5.00 | Logs + metrics |
| Secrets Manager | ~$1.60 | 4 secrets × $0.40/month |
| S3 | ~$0.50 | Terraform state |
| **Total** | **~$196.69** | |

### 12.2 t3.medium vs t4g.medium (Graviton) Decision

**t4g.medium (Graviton) is ~20% cheaper** (ARM-based, ~$0.0336/hr vs ~$0.0416/hr for t3.medium).

**Defense of t3.medium choice:**
- x86 architecture has 100% compatibility with existing container images (no recompile needed)
- Graviton (ARM) requires all images to be built for `linux/arm64` — the current Dockerfiles use `node:20-alpine` and `python:3.11-slim` which have ARM variants, but the CI/CD pipeline uses `--platform linux/amd64`
- For a university demo, the engineering risk and CI/CD changes outweigh the ~$14/month savings
- **To a CTO:** Recommend migrating to Graviton in a follow-up sprint — add `--platform linux/arm64` to Docker builds, validate all dependencies are ARM-compatible, update EKS node group to t4g.medium. Expected savings: ~$14/month (~$168/year) on current scale

### 12.3 DynamoDB On-Demand vs Provisioned — Switching Point

**Current:** PAY_PER_REQUEST (on-demand)  
- Pros: no capacity planning, scales to zero, no waste at low traffic
- Cons: higher per-request cost at sustained high volume

**Switch to provisioned when:**
- Monthly read/write volume is predictable and sustained
- Cost analysis: on-demand costs ~$1.25/million WCU; provisioned is ~$0.00065/WCU-hour
- Break-even: approximately **5–10 million requests/month** sustained
- With 1,000 orders/month current load, on-demand is clearly cheaper
- At 50,000+ orders/month with predictable patterns, provisioned + auto-scaling is better

### 12.4 Reserved Instances — No Upfront vs All Upfront

- **On-Demand:** ~$0.0416/hr per t3.medium — no commitment
- **No Upfront 1yr Reserved:** ~30% discount — pay monthly, cancel/sell anytime
- **All Upfront 1yr Reserved:** ~35% discount — pay everything now, maximum savings

**Why No Upfront is recommended:**  
For a new project, traffic patterns are unpredictable. No Upfront gives 30% savings while preserving flexibility — if requirements change (switch to Graviton, change instance type), you're not locked into a prepaid commitment. All Upfront requires cash flow and the certainty that you'll run t3.medium for 12 months.

### 12.5 Unit Economics — $39.34 per 1,000 Orders

At 1,000 orders/month: $196.69 / (1000/1000) = **$39.34 per 1K orders**

At 50,000 orders/month:  
The infrastructure costs are mostly **fixed** (EKS control plane, RDS, NAT GW) — only DynamoDB and SQS scale proportionally.

Estimated cost at 50K orders:
- Additional DynamoDB reads/writes: ~$2
- Additional SQS messages: ~$0 (still in free tier)
- EKS may need 1 more node (~$30)
- Total: ~$230

**New unit economics:** $230 / (50000/1000) = **~$4.60 per 1K orders** (~88% reduction)

This demonstrates the **economies of scale** of cloud infrastructure — fixed costs amortize over more volume.

### 12.6 Budget Alert at $250 vs $200

The estimate is ~$197. Setting the alert at $200 means:
- Any minor cost spike (extra data transfer, a debug run, a few extra API calls) triggers a false alarm
- $250 provides a **25% buffer** above the expected cost — alerts only on meaningful overspend
- Enough to catch: an accidentally left-on dev cluster, unexpected data transfer, runaway CloudWatch logging
- Not so high that a serious cost anomaly goes unnoticed before the monthly bill arrives

### 12.7 30% Cost Reduction Without Removing Features

Priority order of cuts:
1. **Switch EKS nodes to Spot Instances** → ~60-70% cheaper than On-Demand for nodes (~$40 savings) — risk: spot interruptions, mitigated by multiple AZs and graceful shutdown handlers
2. **Switch to Graviton (t4g.medium)** → ~20% cheaper nodes (~$12 savings)
3. **Single NAT Gateway** (already done) — otherwise could share
4. **Optimize CloudWatch log retention** → set to 30-day retention instead of indefinite (reduces storage cost)
5. **ECR lifecycle policy** (already at 10 images) — could reduce to 5
6. **1-year Reserved Instance for t3.medium nodes** → ~30% off EC2 (~$18 savings)

Best combination for 30% reduction: Spot Instances + Graviton = ~35% reduction while maintaining all features.

---

## 13. AWS Resource Inventory

### 13.1 Complete Resource Map

```
AWS Account: 145023091806 | Region: ap-south-1

NETWORKING
  VPC:              10.0.0.0/16
  Public Subnets:   10.0.1.0/24 (1a), 10.0.2.0/24 (1b)
  Private App:      10.0.11.0/24 (1a), 10.0.12.0/24 (1b)
  Private Data:     10.0.21.0/24 (1a), 10.0.22.0/24 (1b)
  Internet Gateway: 1× (attached to VPC)
  NAT Gateway:      1× (in ap-south-1a public subnet)
  Route Tables:     3× (public, private-app, private-data)

COMPUTE
  EKS Cluster:      cloudmart-eks (v1.32)
  EKS Nodes:        2× t3.medium (ON_DEMAND, min=2, max=3)
  Node Group:       cloudmart-managed-ng (30 GiB gp3)
  OIDC Provider:    (auto-created with EKS)
  ALB:              1× internet-facing (managed by LB Controller)

DATABASES
  RDS:              cloudmart-user-db (db.t4g.micro, PostgreSQL 16, 20 GB gp3)
  RDS Endpoint:     cloudmart-user-db.cjc6cqeq0ser.ap-south-1.rds.amazonaws.com
  DynamoDB:         cloudmart-products (PAY_PER_REQUEST, GSI: category-name-index)

MESSAGING
  SQS Queue:        cloudmart-order-events (visibility=30s, retention=4d)
  SQS DLQ:          cloudmart-order-events-dlq (retention=14d, maxReceive=5)

EMAIL
  SES Identity:     rinduwara0@gmail.com (verified)

CONTAINERS
  ECR Repos:        cloudmart/frontend
                    cloudmart/product-service
                    cloudmart/order-service
                    cloudmart/user-service
                    cloudmart/notification-service

SECURITY & CONFIG
  KMS Key:          alias/cloudmart-kms-{version} (rotation enabled, 7-day deletion)
  Secrets Manager:  cloudmart/shared/user-service/db
                    cloudmart/shared/user-service/jwt
                    cloudmart/shared/notification-service/config
  IAM Roles:        cloudmart-product-service-role (IRSA)
                    cloudmart-order-service-role (IRSA)
                    cloudmart-user-service-role (IRSA)
                    cloudmart-notification-service-role (IRSA)
                    EKS cluster role, EKS node role, ALB controller role

STATE MANAGEMENT
  S3 Bucket:        terraform-cloudmart-state-bucket (versioned, encrypted)
  DynamoDB Locks:   terraform-cloudmart-state-locks (state locking)

OBSERVABILITY
  CloudWatch Logs:  /aws/eks/cloudmart-eks/* (control plane)
                    /cloudmart/prod/* (application logs via CW agent)
  Container Insights: enabled (per-pod CPU/memory metrics)

DNS
  Route 53:         Health checks + failover routing (DR scenario)
```

---

## 14. Cross-Cutting Questions — Quick Answers

### Capital One Breach Mitigations

The Capital One breach used **SSRF (Server-Side Request Forgery)** to hit IMDSv1 at `169.254.169.254` and steal EC2 IAM role credentials.

CloudMart mitigates this with:
1. **IMDSv2 enforcement** (`http_tokens = required` in EKS launch template) — requires a session-token preflight PUT request; SSRF-based exploits typically can't make PUT requests
2. **IRSA instead of node-level IAM roles** — even if IMDSv2 is bypassed, IRSA credentials are pod-specific and namespace-scoped, not a single node-wide role with broad permissions
3. **NetworkPolicy default-deny** — limits which pods can make outbound requests at all
4. **Non-root containers** — reduces blast radius if a container is compromised

### Rolling Update Problem Scenario → Use Blue/Green Instead

**Scenario where rolling update is problematic:**  
A database schema migration that changes a column type in RDS. During rolling update, old pods (v1) and new pods (v2) run simultaneously. v2 expects `order_status` as an enum; v1 writes it as a string. The mixed fleet causes data corruption or errors.

**Blue/Green would be better:** Deploy the entire v2 fleet alongside v1, run smoke tests against v2, then switch the load balancer to point entirely to v2. No mixed-version state.

---

*End of CloudMart Technical Reference — Version generated 2026-06-20*
