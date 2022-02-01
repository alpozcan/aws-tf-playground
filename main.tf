terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.63"
    }
  }

  required_version = ">= 1.0.0"
}

provider "aws" {
  profile = "default"
  region  = "ap-southeast-1"

  default_tags {
    tags = {
      Terraform = "true"
      Environment = "${var.env}"
    }
  }
}

module "infra" {
    source = "./infra"

    env = var.env
}
