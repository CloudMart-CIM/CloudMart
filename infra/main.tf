module "vpc" {
  source = "./modules/vpc"

  vpc_cidr                  = var.vpc_cidr
  availability_zones        = var.availability_zones
  private_app_subnet_cidrs  = var.private_app_subnet_cidrs
  private_data_subnet_cidrs = var.private_data_subnet_cidrs
  public_subnet_cidrs       = var.public_subnet_cidrs
  cluster_name              = var.cluster_name
  single_nat_gateway        = var.single_nat_gateway
  project_name              = var.project_name
  team                      = var.team
  environment               = var.environment
  owner                     = var.owner
}

module "security-groups" {
  source = "./modules/security-groups"

  allowed_ssh_cidrs = var.allowed_ssh_cidrs
  project_name      = var.project_name
  team              = var.team
  environment       = var.environment
  owner             = var.owner
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = var.vpc_cidr
}