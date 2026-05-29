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

output "kms_key_arn" {
  description = "CloudMart KMS key ARN"
  value       = module.kms.kms_key_arn
}

output "user_service_db_secret_arn" {
  description = "Secrets Manager ARN for user-service DB credentials"
  value       = module.secrets-manager.user_service_db_secret_arn
}

output "user_service_jwt_secret_arn" {
  description = "Secrets Manager ARN for user-service JWT secret"
  value       = module.secrets-manager.user_service_jwt_secret_arn
}

output "rds_instance_id" {
  description = "RDS instance ID"
  value       = module.rds.rds_instance_id
}

output "products_table_arn" {
  description = "DynamoDB products table ARN"
  value       = module.dynamodb.products_table_arn
}

output "notification_service_secret_arn" {
  description = "Secrets Manager ARN for notification-service config"
  value       = module.ses.notification_service_secret_arn
}

output "ses_verified_email" {
  description = "SES verified sender email"
  value       = module.ses.ses_verified_email
}

output "order_events_queue_url" {
  description = "SQS order events queue URL"
  value       = module.sqs.order_events_queue_url
}

output "order_events_queue_arn" {
  description = "SQS order events queue ARN"
  value       = module.sqs.order_events_queue_arn
}