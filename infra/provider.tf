terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  backend "s3" {
    bucket         = "terraform-cloudmart-state-bucket"
    key            = "cloudmart/shared/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "terraform-cloudmart-state-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}