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

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

# variable "sg_alb_id" {
#   description = "Security group ID for the ALB"
#   type        = string
# }

variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider for EKS cluster"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the OIDC provider for EKS cluster"
  type        = string
}
