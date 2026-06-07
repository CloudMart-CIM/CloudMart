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
  description = "EKS cluster name"
  type        = string
}

variable "eks_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
}

# aws_subnet.public[*].id,
variable "subnet_ids" {
  description = "List of subnet IDs for EKS cluster"
  type        = list(string)
}

# aws_subnet.private_app[*].id
variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS cluster"
  type        = list(string)
}

# aws_security_group.eks_cluster.id
variable "eks_security_group_id" {
  description = "Security group ID for EKS cluster control plane"
  type        = string
}

# aws_kms_key.cloudmart.arn
variable "kms_key_arn" {
  description = "ARN of KMS key for encrypting EKS secrets"
  type        = string
}

variable "eks_node_instance_types" {
  description = "Instance types for EKS managed node group"
  type        = list(string)
}

variable "eks_node_capacity_type" {
  description = "Capacity type for EKS nodes: ON_DEMAND or SPOT"
  type        = string
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS worker nodes"
  type        = number
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS worker nodes"
  type        = number
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS worker nodes"
  type        = number
}

variable "eks_node_disk_size" {
  description = "Disk size for EKS worker nodes in GiB"
  type        = number
}
