terraform {
  required_version = ">= 1.10"

  required_providers {
    aws        = { source = "hashicorp/aws", version = "~> 6.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.35" }
  }

  # Lock nativo do backend S3 (Terraform >= 1.10) — sem tabela DynamoDB.
  backend "s3" {
    bucket       = "oficina-tfstate-706215605178"
    key          = "infra-k8s/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.regiao

  default_tags {
    tags = {
      Projeto   = "oficina"
      Fase      = "3"
      Ambiente  = var.ambiente
      ManagedBy = "terraform"
      Repo      = "oficina-infra-k8s"
    }
  }
}

# Token gerado na hora: nenhuma credencial de cluster fica no state.
#
# ⚠️ Este provider depende de atributos do cluster que só existem DEPOIS do
# apply. Na primeira execução, rode `terraform apply -target=module.eks`
# antes do apply completo (ver README).
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.regiao]
  }
}
