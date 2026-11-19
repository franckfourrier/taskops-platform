# Fédération GitHub Actions -> AWS par OIDC : aucune clé AWS stockée dans GitHub.
# Deux rôles :
#   - taskops-gha-plan  : lecture seule (PR et planifications sur main)
#   - taskops-gha-apply : modification de l'infra, uniquement depuis un environnement GitHub protégé
terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "taskops-tfstate-219806731917-eu-west-3"
    key          = "global/github-oidc.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-west-3"
  default_tags {
    tags = {
      Project   = "taskops"
      Env       = "global"
      ManagedBy = "terraform"
    }
  }
}

locals {
  repo         = "franckfourrier@251311851/taskops-platform@1462627752"
  state_bucket = "taskops-tfstate-219806731917-eu-west-3"
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

# ---------- Rôle PLAN (lecture seule) ----------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.repo}:pull_request",
        "repo:${local.repo}:ref:refs/heads/main",
      ]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "taskops-gha-plan"
  description          = "GitHub Actions - terraform plan (lecture seule)"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  role       = aws_iam_role.plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "plan_state" {
  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.state.arn
}

# ---------- Rôle APPLY (environnements GitHub protégés uniquement) ----------
data "aws_iam_policy_document" "apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${local.repo}:environment:dev",
        "repo:${local.repo}:environment:prod",
      ]
    }
  }
}

resource "aws_iam_role" "apply" {
  name                 = "taskops-gha-apply"
  description          = "GitHub Actions - terraform apply (environnements proteges)"
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "apply_ec2" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
}

resource "aws_iam_role_policy_attachment" "apply_cloudwatch" {
  role       = aws_iam_role.apply.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

resource "aws_iam_role_policy_attachment" "apply_state" {
  role       = aws_iam_role.apply.name
  policy_arn = aws_iam_policy.state.arn
}

# ---------- Accès au bucket du state (lecture/écriture + verrou) ----------
data "aws_iam_policy_document" "state" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.state_bucket}"]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.state_bucket}/*"]
  }
}

resource "aws_iam_policy" "state" {
  name        = "taskops-tfstate-access"
  description = "Acces au bucket du state Terraform TaskOps"
  policy      = data.aws_iam_policy_document.state.json
}

output "plan_role_arn" {
  value = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  value = aws_iam_role.apply.arn
}
