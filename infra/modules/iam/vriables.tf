variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment tag for shared infrastructure"
  type        = string
}

variable "team" {
  description = "Team or student identifier"
  type        = string
}

variable "owner" {
  description = "Owner email or student email"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA trust policies"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (with https://)"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the KMS key used by DynamoDB, SQS, and Secrets Manager"
  type        = string
}

variable "dynamodb_products_table" {
  description = "Name of the DynamoDB products table"
  type        = string
}

variable "sqs_order_events_queue_arn" {
  description = "ARN of the SQS order events queue"
  type        = string
}

variable "ses_verified_email" {
  description = "SES verified sender email address for notification-service"
  type        = string
}

variable "user_service_db_secret_arn" {
  description = "ARN of the Secrets Manager secret for user-service DB credentials"
  type        = string
}

variable "user_service_jwt_secret_arn" {
  description = "ARN of the Secrets Manager secret for user-service JWT secret"
  type        = string
}
