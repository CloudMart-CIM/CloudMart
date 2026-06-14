locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Team        = var.team
    Owner       = var.owner
    ManagedBy   = "terraform"
    Module      = "cloud-infrastructure-management"
  }
}

# -------------------------
# ALB Security Group
# -------------------------

resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for public Application Load Balancer"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-alb-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTP traffic from internet"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 80
  to_port     = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id

  description = "Allow HTTPS traffic from internet"
  cidr_ipv4   = "0.0.0.0/0"
  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_vpc" {
  security_group_id = aws_security_group.alb.id

  description = "Allow ALB to forward traffic to EKS workloads inside VPC"
  cidr_ipv4   = var.vpc_cidr
  ip_protocol = "-1"
}

# -------------------------
# EKS Cluster Security Group
# -------------------------

resource "aws_security_group" "eks_cluster" {
  name        = "${var.project_name}-eks-cluster-sg"
  description = "Security group for EKS control plane"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-eks-cluster-sg"
  })
}

resource "aws_vpc_security_group_egress_rule" "eks_cluster_egress" {
  security_group_id = aws_security_group.eks_cluster.id

  description = "Allow EKS control plane outbound traffic"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# -------------------------
# EKS Worker Nodes Security Group
# -------------------------

resource "aws_security_group" "eks_nodes" {
  name        = "${var.project_name}-eks-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-eks-nodes-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_self" {
  security_group_id = aws_security_group.eks_nodes.id

  description                  = "Allow worker nodes and pods to communicate with each other"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_alb_http" {
  security_group_id = aws_security_group.eks_nodes.id

  description                  = "Allow ALB to reach frontend pods or node targets over HTTP"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "eks_nodes_from_cluster" {
  security_group_id = aws_security_group.eks_nodes.id

  description                  = "Allow EKS control plane to communicate with worker nodes"
  referenced_security_group_id = aws_security_group.eks_cluster.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "eks_nodes_egress" {
  security_group_id = aws_security_group.eks_nodes.id

  description = "Allow worker nodes outbound traffic through NAT Gateway"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# -------------------------
# RDS PostgreSQL Security Group
# -------------------------

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rds-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_eks_nodes" {
  security_group_id = aws_security_group.rds.id

  description                  = "Allow user-service running on EKS to access PostgreSQL"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
}

# -------------------------
# Bastion Security Group
# -------------------------

resource "aws_security_group" "bastion" {
  name        = "${var.project_name}-bastion-sg"
  description = "Security group for optional bastion host"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-bastion-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh" {
  for_each = toset(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.bastion.id

  description = "Allow SSH to bastion only from trusted IP"
  cidr_ipv4   = each.value
  from_port   = 22
  to_port     = 22
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "bastion_egress" {
  security_group_id = aws_security_group.bastion.id

  description = "Allow bastion outbound traffic"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}

# -------------------------
# VPC Endpoint Security Group
# For later Secrets Manager / CloudWatch interface endpoints
# -------------------------

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-vpc-endpoints-sg"
  description = "Security group for interface VPC endpoints"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc-endpoints-sg"
  })
}

resource "aws_vpc_security_group_ingress_rule" "vpc_endpoints_from_eks_nodes" {
  security_group_id = aws_security_group.vpc_endpoints.id

  description                  = "Allow EKS workloads to access interface endpoints over HTTPS"
  referenced_security_group_id = aws_security_group.eks_nodes.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "vpc_endpoints_egress" {
  security_group_id = aws_security_group.vpc_endpoints.id

  description = "Allow endpoint responses"
  cidr_ipv4   = "0.0.0.0/0"
  ip_protocol = "-1"
}