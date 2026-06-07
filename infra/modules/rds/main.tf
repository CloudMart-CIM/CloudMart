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

resource "aws_db_subnet_group" "rds" {
  name       = "${var.project_name}-rds-subnet-group"
  subnet_ids = var.private_data_subnet_ids
  description = "Subnet group for RDS instances"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rds-subnet-group"
  })
}

resource "aws_db_parameter_group" "postgres_ssl" {
  name        = "${var.project_name}-postgres-ssl-params"
  family      = "postgres16"
  description = "PostgreSQL parameter group enforcing SSL connections"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-postgres-ssl-params"
  })
}

resource "aws_db_instance" "user" {
  identifier = "${var.project_name}-user-db"

  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 30
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [var.rds_security_group_id]
  publicly_accessible    = false

  parameter_group_name = aws_db_parameter_group.postgres_ssl.name

  backup_retention_period = 7
  backup_window           = "18:00-19:00"
  maintenance_window      = "sun:19:30-sun:20:30"

  multi_az                = var.db_multi_az
  deletion_protection     = false
  skip_final_snapshot     = true
  copy_tags_to_snapshot   = true
  apply_immediately       = true

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-user-db"
    Service = "user-service"
  })
}