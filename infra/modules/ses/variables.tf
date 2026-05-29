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

# aws_sqs_queue.order_events.url
variable "sqs_queue_url" {
  description = "SQS queue URL for notification service to send messages"
  type        = string
}