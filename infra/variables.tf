variable "aws_region" {
  description = "AWS region for CloudMart infrastructure"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "cloudmart"
}

variable "environment" {
  description = "Environment tag for shared infrastructure"
  type        = string
  default     = "shared"
}

variable "team" {
  description = "Team or student identifier"
  type        = string
  default     = "individual"
}

variable "owner" {
  description = "Owner email or student email"
  type        = string
  default     = "your-email@example.com"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "cloudmart-eks"
}

variable "vpc_cidr" {
  description = "CIDR block for CloudMart VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Availability zones for subnets"
  type        = list(string)
  default     = ["ap-south-1a", "ap-south-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private application subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "private_data_subnet_cidrs" {
  description = "CIDR blocks for private data subnets"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway for cost saving. Set false for one NAT Gateway per AZ."
  type        = bool
  default     = true
}

variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH into bastion host. Keep empty if bastion is not used."
  type        = list(string)
  default     = []
}

variable "ecr_repositories" {
  description = "List of ECR repositories to create"
  type        = list(string)
  default     = []
}

variable "db_name" {
  description = "PostgreSQL database name for user-service"
  type        = string
  default     = "cloudmart_users"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "cloudmartadmin"
}

variable "db_password" {
  description = "PostgreSQL master password. If not set, a random password will be generated and stored in Secrets Manager."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class for PostgreSQL"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage for RDS PostgreSQL in GB"
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Enable Multi-AZ for RDS. Keep false for cost saving."
  type        = bool
  default     = false
}

variable "ses_verified_email" {
  description = "Email address to verify in Amazon SES for sending notifications"
  type        = string
  default     = ""
}

variable "key_version" {
  description = "Version identifier for KMS key alias (e.g., v1, v2)"
  type        = string
}