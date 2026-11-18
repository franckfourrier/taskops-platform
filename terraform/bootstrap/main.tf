# Bootstrap : crée le bucket S3 qui stockera le state Terraform du projet.
# Exécuté UNE fois, avec un state local (le bucket ne peut pas stocker son propre state).
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-west-3"
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project   = "taskops"
      Env       = "shared"
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "taskops-tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # Protection : impossible de détruire ce bucket par un simple terraform destroy
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Les anciennes versions du state sont supprimées après 90 jours (coût maîtrisé)
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

output "bucket_name" {
  value = aws_s3_bucket.tfstate.bucket
}
