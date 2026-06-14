# ADR-002: Database Technology for User-Service

## Status 
Accepted

## Context 
The user-service manages registration, authentication (JWT), and profile data. It requires strong consistency for credential storage, relational queries (lookup by email, user ID), ACID transactions for registration, and encrypted storage with SSL in transit. Passwords must be hashed with bcrypt before persistence. The assignment mandates a managed relational database (PostgreSQL) for user-service data. CloudMart is a low-traffic startup deployment with a small user base during development and assessment.

## Decision 
We selected Amazon RDS for PostgreSQL (db.t4g.micro, engine 16) deployed in private data subnets with KMS encryption at rest, rds.force_ssl = 1, and credentials stored in AWS Secrets Manager. 

## Consequences 
- Positive: PostgreSQL provides mature tooling (parameter groups, automated 7-day backups, PITR for disaster recovery). The adapter pattern in user-service (DB_BACKEND=postgres) integrates cleanly with Secrets Manager via IRSA. SSL enforcement and KMS encryption satisfy mandatory security controls.  
- Negative: Single-AZ deployment (db_multi_az = false) reduces availability during AZ failure; connection pooling must be managed at the application layer (gunicorn workers). RDS has a fixed monthly cost even at zero traffic, unlike pure serverless options. 

 
## Alternatives Considered 

| Option | Fit for user data | Cost (approx.) | Why rejected |
|--------|-------------------|----------------|--------------|
| Amazon DynamoDB  | Poor - no native joins; email uniqueness requires careful GSI design; JWT session patterns awkward  | Pay-per-request, very low at small scale | Wrong data model for relational user profiles; assignment explicitly requires PostgreSQL for user-service  |
| Aurora Serverless v2 | Excellent - auto scaling PostgreSQL  | ~$45+/month minimum ACU  | Over-provisioned and over-budget for a student deployment with near-zero production traffic  |
| RDS PostgreSQL (db.t4g.micro) | Excellent — full SQL, SSL, managed backups, point-in time recovery  | ~$12–15/month (free-tier eligible)  | **Selected** - meets all functional and compliance requirements at lowest managed PostgreSQL cost |