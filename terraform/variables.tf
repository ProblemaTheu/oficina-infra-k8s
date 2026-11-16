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
  description = "Mínimo de nós. 3 na Fase 4: OS + Billing + Execution + nri-bundle não cabem nos 11 pods/nó do t3.small (limite de ENI do VPC CNI)"
  type        = number
  default     = 3
}

variable "node_max" {
  description = "Teto do node group. Sem Cluster Autoscaler (corte 3) fica sempre em node_min; o slot extra só existe para o EKS conseguir substituir um nó numa atualização"
  type        = number
  default     = 4
}

# Principals por apelido → caminho do ARN dentro da conta. O ID da conta vem
# de aws_caller_identity (main.tf): trocar de conta não muda código.
# Mapa, e não lista: as chaves viram as chaves das access entries no state.
variable "admin_principals" {
  description = "Principals IAM com acesso administrativo ao cluster: apelido → caminho do ARN (user/..., role/...)"
  type        = map(string)
  default = {
    admin-cli             = "user/admin-cli"
    gha-oficina-infra-k8s = "role/gha-oficina-infra-k8s"

    # Login do console na conta da organização (Builder ID / acesso gerenciado
    # da AWS). Na conta da Fase 3 era o root; nesta, o root não tem login.
    console = "role/managed/AccountFullAccessRole"
  }
}

variable "cd_role" {
  description = "Role do CD da aplicação — acesso Edit restrito ao namespace, nunca ClusterAdmin"
  type        = string
  default     = "gha-oficina-app"
}

# Fase 4: cada microsserviço novo tem namespace próprio e uma role de CD (do
# bootstrap) com Edit só nele. O OS Service continua no namespace da Fase 3
# (local.ns), via cd_role.
variable "servicos" {
  description = "Microsserviços da Fase 4: namespace e nome da role de CD de cada um"
  type = map(object({
    namespace = string
    cd_role   = string
  }))
  default = {
    billing = {
      namespace = "billing-prod"
      cd_role   = "gha-oficina-billing"
    }
    execution = {
      namespace = "execution-prod"
      cd_role   = "gha-oficina-execution"
    }
  }
}

variable "plan_role" {
  description = "Role read-only usada pelo `terraform plan` em Pull Request deste repositório — só View no cluster"
  type        = string
  default     = "gha-oficina-infra-k8s-plan"
}
