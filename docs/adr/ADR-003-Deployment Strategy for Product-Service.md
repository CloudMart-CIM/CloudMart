# ADR-002: Database Technology for User-Service

## Status 
Accepted

## Context 
Product-service is the highest-read microservice in CloudMart: the frontend queries it on every browse and search, and order-service calls it internally for stock checks. It runs 2 replicas in cloudmart-prod with an HPA scaling to 6 replicas at 60% CPU. The assignment requires rolling updates with maxSurge: 1 and maxUnavailable: 0, plus a health-check gate before full promotion. Our RTO target is under 15 minutes (see Section 6), and the team has moderate Kubernetes operational experience — comfortable with kubectl rollout but not with Argo Rollouts or service mesh tooling. 

## Decision 
We adopted native Kubernetes rolling updates for product-service (and all other services), configured as: 

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
```

Readiness probes on /ready gate traffic to new pods before old pods terminate.

## Consequences 
- Positive: Rolling updates integrate directly with GitHub Actions image pushes and kubectl rollout status. Failed readiness probes automatically stall the rollout, keeping the previous ReplicaSet serving traffic.    
- Negative: No gradual traffic shifting; issues may affect all users immediately after rollout. 

 
## Alternatives Considered 

| Strategy | Downtime risk | Operational complexity  | Why rejected |
|--------|-----------------|-------------------------|--------------|
| Blue/green   | Near zero - instant traffic switch | Requires duplicate Deployment or dual Ingress; 2× resource cost during cut over | Unjustified for 2 replica catalogue service; doubles compute spend during every release |
| Canary (Argo Rollout / Flagger) | Near zero - gradual traffic shift  | Requires controller install, metric provider, error-rate gates  | Best for high-traffic production; adds tooling not yet  operationalize |
| Rolling update (native K8s)  | Zero planned downtime with maxUnavailable: 0 | Built-in; works with existing probes and CI pipeline | **Selected** - meets mandatory requirements with no additional infrastructure |
