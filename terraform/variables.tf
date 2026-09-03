variable "regiao" {
  description = "Região AWS"
  type        = string
  default     = "us-east-1"
}

variable "projeto" {
  description = "Prefixo dos recursos"
  type        = string
  default     = "oficina"
}

# Corte 10 (ambiente único): não há for_each de ambientes. `prod` é fixo.
variable "ambiente" {
  description = "Ambiente único da Fase 3 — homologação foi dispensada pela disciplina"
  type        = string
  default     = "prod"
}

variable "vpc_cidr" {
  description = "CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

# ⚠️ Versão FORA do standard support custa US$ 0,60/h em vez de US$ 0,10/h.
# Confira antes de alterar:
#   aws eks describe-cluster-versions --region us-east-1 \
#     --query 'clusterVersions[?versionStatus==`STANDARD_SUPPORT`].[clusterVersion,endOfStandardSupportDate]' --output table
variable "eks_versao" {
  description = "Versão do Kubernetes no EKS (manter em standard support)"
  type        = string
  default     = "1.36"
}

variable "node_instance_type" {
  description = "Tipo de instância dos nós"
  type        = string
  default     = "t3.small"
}

variable "node_min" {
  description = "Mínimo de nós"
  type        = number
  default     = 2
}

variable "node_max" {
  description = "Teto do node group. Sem Cluster Autoscaler (corte 3) fica sempre em 2; o 3º slot só existe para o EKS conseguir substituir um nó numa atualização"
  type        = number
  default     = 3
}

variable "admin_principal_arns" {
  description = "Principals IAM com acesso administrativo ao cluster (uma entrada por pessoa)"
  type        = list(string)
  default = [
    "arn:aws:iam::706215605178:user/admin-cli",
    "arn:aws:iam::706215605178:role/gha-oficina-infra-k8s",
  ]
}

variable "cd_role_arn" {
  description = "Role do CD da aplicação — acesso Edit restrito ao namespace, nunca ClusterAdmin"
  type        = string
  default     = "arn:aws:iam::706215605178:role/gha-oficina-app"
}
