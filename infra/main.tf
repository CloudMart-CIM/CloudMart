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

module "ecr" {
  source = "./modules/ecr"

  project_name     = var.project_name
  team             = var.team
  environment      = var.environment
  owner            = var.owner
  ecr_repositories = var.ecr_repositories
}

module "kms" {
  source = "./modules/kms"

  project_name = var.project_name
  team         = var.team
  environment  = var.environment
  owner        = var.owner
}

module "secrets-manager" {
  source = "./modules/secrets-manager"

  project_name = var.project_name
  team         = var.team
  environment  = var.environment
  owner        = var.owner
  db_host      = module.rds.user_db_endpoint
  db_port      = module.rds.user_db_port
  db_name      = var.db_name
  db_username  = var.db_username
  db_password  = var.db_password
}

module "sqs" {
  source = "./modules/sqs"

  project_name = var.project_name
  team         = var.team
  environment  = var.environment
  owner        = var.owner
  kms_key_arn  = module.kms.kms_key_arn
}

module "ses" {
  source = "./modules/ses"

  project_name       = var.project_name
  team               = var.team
  environment        = var.environment
  owner              = var.owner
  aws_region         = var.aws_region
  ses_verified_email = var.ses_verified_email
  kms_key_arn        = module.kms.kms_key_arn
  sqs_queue_url      = module.sqs.order_events_queue_url
}

module "dynamodb" {
  source = "./modules/dynamodb"

  project_name = var.project_name
  team         = var.team
  environment  = var.environment
  owner        = var.owner
  kms_key_arn  = module.kms.kms_key_arn
}

module "rds" {
  source = "./modules/rds"

  project_name            = var.project_name
  team                    = var.team
  environment             = var.environment
  owner                   = var.owner
  db_name                 = var.db_name
  db_username             = var.db_username
  db_password             = var.db_password
  db_instance_class       = var.db_instance_class
  db_allocated_storage    = var.db_allocated_storage
  db_multi_az             = var.db_multi_az
  private_data_subnet_ids = module.vpc.private_data_subnet_ids
  kms_key_arn             = module.kms.kms_key_arn
  rds_security_group_id   = module.security-groups.rds_security_group_id
}