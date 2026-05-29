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