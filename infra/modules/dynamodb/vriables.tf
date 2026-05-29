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

#  aws_kms_key.cloudmart.arn
variable "kms_key_arn" {
  description = "KMS key ARN for server-side encryption"
  type        = string
}