terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # State distant : bucket créé par terraform/bootstrap.
  # La clé (dev/prod) est fournie à l'init : terraform init -backend-config=envs/dev.s3.tfbackend
  backend "s3" {
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true # verrouillage natif S3 (pas de DynamoDB)
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "taskops"
      Env       = var.env
      ManagedBy = "terraform"
    }
  }
}
