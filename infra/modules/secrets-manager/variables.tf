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

variable "db_name" {
  description = "PostgreSQL database name for user-service"
  type        = string
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
}

variable "db_password" {
  description = "PostgreSQL master password (should be provided via tfvars or environment variable)"
  type        = string
  sensitive   = true
}

variable "db_host" {
  description = "RDS endpoint address for user-service database"
  type        = string
}

variable "db_port" {
  description = "RDS endpoint port for user-service database"
  type        = number
}

variable "ses_verified_email" {
  description = "Email address to verify in SES for sending notifications"
  type        = string
}

variable "aws_region" {
  description = "AWS region for SES and SQS resources"
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN for SES secrets encryption"
  type        = string
}

variable "sqs_queue_url" {
  description = "SQS queue URL for notification service to send messages"
  type        = string
}