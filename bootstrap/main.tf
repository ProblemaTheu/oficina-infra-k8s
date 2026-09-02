# Bootstrap — recursos que precisam existir ANTES de qualquer outro Terraform.
# Aplicado UMA vez, com backend local. O state deste diretório é o único que
# não vive no S3 (é ele que cria o S3).

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Projeto   = "oficina"
      Fase      = "3"
      ManagedBy = "terraform"
      Repo      = "oficina-infra-k8s/bootstrap"
    }
  }
}

data "aws_caller_identity" "atual" {}

locals {
  org   = "ProblemaTheu"
  repos = ["oficina-app", "oficina-lambda-auth", "oficina-infra-k8s", "oficina-infra-db"]
}

# ── State remoto ──────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "tfstate" {
  bucket        = "oficina-tfstate-${data.aws_caller_identity.atual.account_id}"
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration { status = "Enabled" }
}

# O state guarda segredos em texto puro: criptografia em repouso é obrigatória
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lock de state: a partir do Terraform 1.10 o backend S3 tem lock nativo
# (use_lockfile = true), então NÃO existe tabela DynamoDB aqui.

# ── OIDC: GitHub Actions assume role sem chave de longa duração ───────────────
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# Uma role por repositório — o `sub` restringe QUAL repo e QUAL branch pode assumir
resource "aws_iam_role" "github" {
  for_each = toset(local.repos)
  name     = "gha-${each.value}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        # Uma branch de feature NÃO consegue aplicar nada na AWS
        StringLike = {
          "token.actions.githubusercontent.com:sub" = [
            "repo:${local.org}/${each.value}:ref:refs/heads/main",
            "repo:${local.org}/${each.value}:environment:prod",
          ]
        }
      }
    }]
  })
}

# Repos de infra e lambda: acesso amplo (destravar o prazo).
# TODO F3-1.7: restringir por tag antes da entrega e documentar no README.
resource "aws_iam_role_policy_attachment" "infra_admin" {
  for_each   = toset(["oficina-infra-k8s", "oficina-infra-db", "oficina-lambda-auth"])
  role       = aws_iam_role.github[each.value].name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Repo da aplicação: só precisa achar o cluster e ler parâmetros — nada mais.
resource "aws_iam_role_policy" "app" {
  name = "deploy-eks"
  role = aws_iam_role.github["oficina-app"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["eks:DescribeCluster", "eks:ListClusters"]
      Resource = "*"
      }, {
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:us-east-1:${data.aws_caller_identity.atual.account_id}:parameter/oficina/*"
    }]
  })
}

# ── Saídas usadas por todos os outros repositórios ────────────────────────────
output "bucket_state" { value = aws_s3_bucket.tfstate.bucket }
output "account_id" { value = data.aws_caller_identity.atual.account_id }
output "roles" {
  value = { for k, r in aws_iam_role.github : k => r.arn }
}
