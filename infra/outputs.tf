# -------------------------
# VPC Module Outputs
# -------------------------

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "CloudMart VPC CIDR block"
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "Private application subnet IDs for EKS worker nodes"
  value       = module.vpc.private_app_subnet_ids
}

output "private_data_subnet_ids" {
  description = "Private data subnet IDs for RDS"
  value       = module.vpc.private_data_subnet_ids
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs"
  value       = module.vpc.nat_gateway_ids
}

# -------------------------
# Security Group Module Outputs
# -------------------------

output "alb_security_group_id" {
  description = "Security group ID for ALB"
  value       = module.security-groups.alb_security_group_id
}

output "eks_cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  value       = module.security-groups.eks_cluster_security_group_id
}

output "eks_nodes_security_group_id" {
  description = "Security group ID for EKS worker nodes"
  value       = module.security-groups.eks_nodes_security_group_id
}

output "rds_security_group_id" {
  description = "Security group ID for RDS PostgreSQL"
  value       = module.security-groups.rds_security_group_id
}

output "bastion_security_group_id" {
  description = "Security group ID for optional bastion host"
  value       = module.security-groups.bastion_security_group_id
}

output "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC interface endpoints"
  value       = module.security-groups.vpc_endpoints_security_group_id
}

# -------------------------
# KMS Module Outputs
# -------------------------

output "kms_key_arn" {
  description = "CloudMart KMS key ARN"
  value       = module.kms.kms_key_arn
}

# -------------------------
# Secret Manager Module Outputs
# -------------------------

output "user_service_db_secret_arn" {
  description = "Secrets Manager ARN for user-service DB credentials"
  value       = module.secrets-manager.user_service_db_secret_arn
}

output "user_service_jwt_secret_arn" {
  description = "Secrets Manager ARN for user-service JWT secret"
  value       = module.secrets-manager.user_service_jwt_secret_arn
}

# -------------------------
# RDS Module Outputs
# -------------------------

output "rds_instance_id" {
  description = "RDS instance ID"
  value       = module.rds.rds_instance_id
}

# -------------------------
# DynamoDB Module Outputs
# -------------------------

output "products_table_arn" {
  description = "DynamoDB products table ARN"
  value       = module.dynamodb.products_table_arn
}

output "products_table_name" {
  description = "DynamoDB products table name"
  value       = module.dynamodb.products_table_name
}

# -------------------------
# SES Module Outputs
# -------------------------
output "notification_service_secret_arn" {
  description = "Secrets Manager ARN for notification-service config"
  value       = module.secrets-manager.notification_service_secret_arn
}

output "ses_verified_email" {
  description = "SES verified sender email"
  value       = module.ses.ses_verified_email
}

# -------------------------
# SQS Module Outputs
# -------------------------

output "order_events_queue_url" {
  description = "SQS order events queue URL"
  value       = module.sqs.order_events_queue_url
}

output "order_events_queue_arn" {
  description = "SQS order events queue ARN"
  value       = module.sqs.order_events_queue_arn
}

# -------------------------
# EKS Module Outputs
# -------------------------

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.eks_cluster_name
}

output "eks_cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.eks_cluster_arn
}

output "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint"
  value       = module.eks.eks_cluster_endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.eks_cluster_certificate_authority_data
  sensitive   = true
}

output "eks_node_group_name" {
  description = "EKS managed node group name"
  value       = module.eks.eks_node_group_name
}

output "eks_node_role_arn" {
  description = "EKS node IAM role ARN"
  value       = module.eks.eks_node_role_arn
}

output "eks_cluster_role_arn" {
  description = "EKS cluster IAM role ARN"
  value       = module.eks.eks_cluster_role_arn
}

output "alb_controller_role_arn" {
  description = "IAM role ARN for AWS Load Balancer Controller"
  value       = module.alb.alb_controller_role_arn
}