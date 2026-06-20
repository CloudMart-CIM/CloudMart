# ADR-001: Kubernetes Worker Node Instance Type
## Status 
Accepted

## Context 
CloudMart runs five containerised microservices on Amazon EKS with a minimum 
of two worker nodes and a maximum of three (cluster autoscaler range). Each production 
Deployment requests between 50m–100m CPU and 64Mi–128Mi memory per pod, with two 
replicas for four services and one replica for notification-service. At peak, the cluster must 
comfortably schedule 9+ pods while leaving headroom for rolling updates (maxSurge: 1) and 
HPA scale-out on product-service and order-service. Cost is a primary constraint: the 
assignment targets free-tier or minimal-cost usage, and the team operates in ap-south-1 on on
demand capacity. 

## Decision 
 We selected t3.medium (2 vCPU, 4 GiB RAM, x86 burstable) as the EKS managed 
node group instance type, with on-demand capacity and a desired size of 2 nodes. 

## Consequences 
- Positive: Two t3.medium nodes provide adequate memory (~8 GiB cluster-wide) for 
all services, kube-system pods, and one surge pod during rolling updates. Burstable 
CPU credits suit intermittent e-commerce traffic. On-demand pricing avoids spot 
interruption during demos and assessment.  
- Negative: x86 t3.medium costs more than ARM equivalents; burstable instances can 
throttle under sustained CPU load unless credits are monitored. Scaling beyond three 
nodes would increase cost linearly.

 
## Alternatives Considered 

| Instance type | vCPU / RAM | Approx. on-demand cost (ap-south-1, per node/month) | Why rejected |
|--------------|------------|-----------------------------------------------------|--------------|
| t3.small | 2 / 2 GiB | ~$15 | Insufficient memory to run 9 pods plus system daemons; risk of OOM under HPA scale-out |
| t4g.medium (Graviton/ARM) | 2 / 4 GiB | ~$24 (~20% cheaper than t3.medium) | Requires ARM-compatible images; added build/test complexity for a mixed Python/Node stack within project timeline |
| m6i.large (compute-optimized) | 2 / 8 GiB | ~$70 | Higher cost with unused RAM; CloudMart workloads are I/O-bound (API + DB calls), not CPU-saturated compute |