# CloudMart — Starter Code

**IS 4630 Cloud Infrastructure Management | University of Moratuwa**

CloudMart is a microservices-based e-commerce platform used as the group assignment project for IS 4630. This repository contains fully working starter code for all five services.

## Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│   Frontend   │────▶│  product-service │     │   user-service   │
│  (React/Nginx│────▶│  (Flask :8001)   │     │  (Flask :8003)   │
│   :80/443)   │────▶│                  │     │  JWT + bcrypt    │
│              │     └──────────────────┘     └──────────────────┘
│              │────▶┌──────────────────┐
│              │     │  order-service   │────▶ product-service
└──────────────┘     │  (Express :8002) │        (stock check)
                     │                  │
                     └───────┬──────────┘
                             │ publishes
                             ▼
                     ┌──────────────────┐
                     │  Message Queue   │
                     │  (in-memory/SQS/ │
                     │   Pub-Sub/SB)    │
                     └───────┬──────────┘
                             │ consumes
                             ▼
                     ┌──────────────────┐
                     │ notification-svc │
                     │  (Node.js :8004) │
                     │  sends emails    │
                     └──────────────────┘
```

## Services

| Service | Port | Language | Description |
|---------|------|----------|-------------|
| **product-service** | 8001 | Python/Flask | Product catalogue CRUD, search, categories, stock management |
| **order-service** | 8002 | Node.js/Express | Order creation, status management, publishes events to queue |
| **user-service** | 8003 | Python/Flask | User registration, JWT authentication, profile management |
| **notification-service** | 8004 | Node.js | Consumes order events, sends email notifications |
| **frontend** | 80 | React/Nginx | SPA with product browsing, cart, checkout, order history |

## Quick Start (Local Development)

### Prerequisites

- Docker Desktop installed and running
- Git

### Run with Docker Compose

```bash
git clone <your-repo-url>
cd cloudmart-starter
docker compose up --build
```

Open http://localhost:3000 in your browser.

**Demo credentials:** `alice@cloudmart.example` / `password123`

### Test individual services

```bash
# Health checks
curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:8003/health
curl http://localhost:8004/health

# List products
curl http://localhost:8001/products

# Search products
curl "http://localhost:8001/products?search=headphone"

# Filter by category
curl "http://localhost:8001/products?category=electronics"

# Register a new user
curl -X POST http://localhost:8003/auth/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Test User","email":"test@example.com","password":"password123"}'

# Login
curl -X POST http://localhost:8003/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@cloudmart.example","password":"password123"}'

# Create an order (use the token from login response)
curl -X POST http://localhost:8002/orders \
  -H "Content-Type: application/json" \
  -d '{"userId":"user-001","items":[{"productId":"prod-001","quantity":1}]}'

# Check notification log
curl http://localhost:8004/notifications
```

## Cloud Adapter Pattern

All services use an **adapter pattern** for cloud backends. By default, they run with in-memory data stores (no cloud credentials needed). To connect to cloud-managed services, set the appropriate environment variables:

### Product Service

| Variable | Values | Description |
|----------|--------|-------------|
| `STORE_BACKEND` | `memory` (default), `dynamodb`, `firestore`, `cosmosdb` | Data store backend |
| `DYNAMODB_TABLE` | Table name | Required when STORE_BACKEND=dynamodb |
| `FIRESTORE_COLLECTION` | Collection name | Required when STORE_BACKEND=firestore |

### Order Service

| Variable | Values | Description |
|----------|--------|-------------|
| `QUEUE_BACKEND` | `memory` (default), `sqs`, `pubsub`, `servicebus` | Message queue backend |
| `SQS_QUEUE_URL` | Queue URL | Required when QUEUE_BACKEND=sqs |
| `PUBSUB_TOPIC` | Topic name | Required when QUEUE_BACKEND=pubsub |

### User Service

| Variable | Values | Description |
|----------|--------|-------------|
| `DB_BACKEND` | `memory` (default), `postgres` | Database backend |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | Connection details | Required when DB_BACKEND=postgres |
| `JWT_SECRET` | Secret string | **Change this in production!** |

### Notification Service

| Variable | Values | Description |
|----------|--------|-------------|
| `QUEUE_BACKEND` | `memory` (default), `sqs`, `pubsub`, `servicebus` | Queue to poll for events |
| `EMAIL_BACKEND` | `console` (default), `ses`, `sendgrid` | Email sending backend |
| `FROM_EMAIL` | Email address | Sender email for cloud backends |

## Assignment Tasks

Your group needs to:

1. **Containerise** — The Dockerfiles are provided as best-practice examples. Review and understand them.
2. **Push to registry** — Push all 5 images to your cloud provider's container registry.
3. **Implement cloud adapters** — Replace the in-memory stores with real cloud databases and queues.
4. **Deploy to Kubernetes** — Create Deployments, Services, Ingress, ConfigMaps, and Secrets.
5. **Secure** — Add NetworkPolicy, workload identity, WAF, and threat detection.
6. **Build CI/CD** — Automate test → build → scan → push → deploy.
7. **Monitor** — Set up dashboards, logging, and alerts.
8. **Optimise costs** — Tag resources, analyse spend, right-size instances.

See the full assignment brief for detailed requirements.

## Project Structure

```
cloudmart-starter/
├── docker-compose.yml          # Local development orchestration
├── README.md                   # This file
├── services/
│   ├── product-service/
│   │   ├── app.py              # Flask app with in-memory + cloud adapters
│   │   ├── requirements.txt
│   │   ├── Dockerfile          # Multi-stage, non-root, healthcheck
│   │   └── .dockerignore
│   ├── order-service/
│   │   ├── src/index.js        # Express app with queue adapters
│   │   ├── package.json
│   │   ├── Dockerfile
│   │   └── .dockerignore
│   ├── user-service/
│   │   ├── app.py              # Flask app with JWT + bcrypt
│   │   ├── requirements.txt
│   │   ├── Dockerfile
│   │   └── .dockerignore
│   ├── notification-service/
│   │   ├── src/index.js        # Queue consumer + email sender
│   │   ├── package.json
│   │   ├── Dockerfile
│   │   └── .dockerignore
│   └── frontend/
│       ├── src/                # React SPA source
│       ├── public/
│       ├── nginx.conf          # Reverse proxy config
│       ├── package.json
│       ├── Dockerfile          # Multi-stage: npm build → nginx
│       └── .dockerignore
├── k8s/                        # Kubernetes manifest templates
│   ├── namespace.yaml
│   ├── product-service.yaml
│   ├── order-service.yaml
│   ├── user-service.yaml
│   ├── notification-service.yaml
│   ├── frontend.yaml
│   ├── configmap.yaml
│   └── network-policy.yaml
└── docs/adr/                   # Architecture Decision Records go here
```

## Cloud Provider

**Chosen provider:** _[Your group fills this in: AWS / GCP / Azure]_

## Team Members

| Name | Student ID | Responsibilities |
|------|-----------|-----------------|
| | | |
| | | |
| | | |
| | | |
| | | |

## AI Tool Disclosure

_[If your group used GitHub Copilot, ChatGPT, Claude, or any AI assistant, disclose here: which tools, for which tasks, and what review process you applied.]_

---

*IS 4630 Cloud Infrastructure Management | University of Moratuwa | Academic Year 2025/2026*


# CloudMart Deployment Guide

## Phase 1: Preparation

### 1. Configure AWS CLI
Install the AWS CLI and authenticate with your new AWS account credentials:

```bash
aws configure
```

Verify the configuration:

```bash
aws sts get-caller-identity
```

### 2. Install Prerequisites
Ensure the following tools are installed on your machine:

- `terraform`
- `kubectl`
- `helm`
- `docker`

---

## Phase 2: Bootstrap Infrastructure

### 1. Deploy Terraform Backend

```bash
cd infra/backend/
terraform init
terraform plan
terraform apply
```

### 2. Configure Main Terraform Backend Context

Update the backend configuration as required for your environment.

### 3. Deploy Main Infrastructure

```bash
cd ../   # You should now be in the infra/ directory
```

Review `terraform.tfvars` and update any environment variables, SSH key names, or domains if necessary. Ensure `aws_region` is set correctly.

Run the deployment:

```bash
terraform init
terraform plan
terraform apply
```

> **Note:** This step provisions your VPC, ECR repositories, EKS cluster, RDS, DynamoDB, SQS, SES, and other required services.

---

## Phase 3: Setup EKS Cluster & ALB Controller

### 1. Update Kubeconfig

Connect `kubectl` to your newly created EKS cluster:

```bash
aws eks update-kubeconfig --region <your-region> --name <your-cluster-name>
```

### 2. Deploy ALB Identity/Roles

```bash
cd infra/alb/
terraform init
terraform apply
```

> This generates the IAM Roles and Trust Policies required for the AWS Load Balancer Controller to operate.

### 3. Install the AWS Load Balancer Controller

Deploy the AWS Load Balancer Controller via Helm to your EKS cluster using the Service Account and IAM Role generated in the previous step.

---

## Phase 4: Build and Push Docker Images

### 1. Authenticate Docker with ECR

```bash
aws ecr get-login-password --region <your-region> | docker login --username AWS --password-stdin <new-account-id>.dkr.ecr.<your-region>.amazonaws.com
```

### 2. Build & Push Each Service

Repeat the following steps for each service: `frontend`, `notification-service`, `order-service`, `product-service`, and `user-service`.

```bash
cd services/<service-name>

# Build the image
docker build -t cloudmart-<service-name> .

# Tag the image with your new ECR URI
docker tag cloudmart-<service-name>:latest <new-account-id>.dkr.ecr.<your-region>.amazonaws.com/cloudmart-<service-name>:latest

# Push the image
docker push <new-account-id>.dkr.ecr.<your-region>.amazonaws.com/cloudmart-<service-name>:latest
```

---

## Phase 5: Update & Apply Kubernetes Manifests

### 1. Update Manifest Image URIs

Go through the files in the `deployments/` directory (e.g., `frontend.yaml`) and replace the old AWS account ID/Region in the `image:` fields with your new account's ECR URIs.

### 2. Update Environment Configurations

Open `configmap.yaml` and update all AWS endpoints:

- Replace old **RDS Database endpoints**
- Replace old **DynamoDB table ARNs**
- Replace old **SQS Queue URLs**

with the new ones provisioned in Phase 2. You can retrieve these with:

```bash
terraform output   # Run from the infra/ directory
```

### 3. Deploy to EKS

```bash
kubectl apply -f k8s/namespaces/
kubectl apply -f k8s/serviceaccounts/
kubectl apply -f k8s/configmaps/
kubectl apply -f k8s/network-policies/
kubectl apply -f k8s/deployments/
```

---

## Phase 6: Verification

### 1. Verify Pods Are Running

```bash
kubectl get pods -A
```

### 2. Get the ALB Endpoint

Retrieve the Application Load Balancer endpoint created by the Ingress:

```bash
kubectl get ingress -n <your-namespace>
```

---

## Destroy All Resources

To tear down all provisioned infrastructure:

```bash
terraform destroy -auto-approve
```

