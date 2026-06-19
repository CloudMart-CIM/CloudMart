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