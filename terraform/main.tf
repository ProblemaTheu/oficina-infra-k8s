# Plataforma da oficina: rede + cluster EKS.
# O banco gerenciado vive em oficina-infra-db e lê esta rede pela SSM.

data "aws_availability_zones" "disponiveis" {
  state = "available"
}

locals {
  azs     = slice(data.aws_availability_zones.disponiveis.names, 0, 2)
  cluster = var.projeto
  ns      = "${var.projeto}-${var.ambiente}"
}

# ── Rede ──────────────────────────────────────────────────────────────────────
#
# ⏱️ Corte 2: SEM NAT Gateway. Os nós ficam em subnet pública, com IP público,
# e saem para a internet pelo Internet Gateway. Economiza ~US$ 32/mês e a hora
# de setup. As subnets privadas continuam existindo — o RDS mora nelas e não
# precisa de saída para a internet.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.projeto
  cidr = var.vpc_cidr
  azs  = local.azs

  private_subnets = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i, _ in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 10)]

  enable_nat_gateway   = false
  enable_dns_hostnames = true

  # Sem isto os nós sobem sem IP público e não conseguem falar com o EKS.
  map_public_ip_on_launch = true

  # Descoberta de subnets pelo controlador de load balancer do EKS.
  # A tag de cluster é o que faz o Service type: LoadBalancer (dia 3)
  # escolher estas subnets para o NLB.
  public_subnet_tags = {
    "kubernetes.io/role/elb"                 = 1
    "kubernetes.io/cluster/${local.cluster}" = "shared"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"        = 1
    "kubernetes.io/cluster/${local.cluster}" = "shared"
  }
}

# SG das Lambdas na VPC. Criado aqui porque a rede é deste repositório;
# o oficina-lambda-auth apenas consome o ID pela SSM.
resource "aws_security_group" "lambda" {
  name        = "${var.projeto}-lambda"
  description = "Lambdas de autenticacao anexadas a VPC"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Saida liberada (RDS e servicos AWS)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── Cluster EKS ───────────────────────────────────────────────────────────────
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.25"

  name               = local.cluster
  kubernetes_version = var.eks_versao

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.public_subnets # nós (corte 2)
  control_plane_subnet_ids = module.vpc.private_subnets

  endpoint_public_access = true # kubectl da máquina e do CI

  # A chave KMS que cifra os secrets no etcd fica nos padrões do módulo.
  # Tínhamos cortado para o destroy sair 100% limpo — o `destroy` só AGENDA a
  # exclusão de uma chave KMS (7 dias no mínimo, ~US$ 0,23 nesse intervalo) —
  # mas o cluster foi criado com a criptografia ligada e a AWS não permite
  # desligá-la depois. Recriar custaria ~25 min por US$ 0,23. Fica como está;
  # o destroy.sh lembra de conferir a chave pendente no fim.
  #
  # Sem esta lista, o módulo grava como administrador da chave QUEM RODOU o
  # Terraform — e a policy mudaria a cada execução (admin-cli local, role de
  # plan no PR, role de apply no CI). Os mesmos principals que administram o
  # cluster administram a chave; o root já tem kms:* pelo statement padrão.
  kms_key_administrators = [for arn in values(var.admin_principal_arns) : arn if !endswith(arn, ":root")]

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = {}
    metrics-server         = {} # o HPA depende disto
  }

  eks_managed_node_groups = {
    default = {
      # Explícito, e não herdado do cluster: sem isto o node group resolve a
      # versão a partir de um atributo do cluster, o que deixa um `count` do
      # módulo desconhecido em plan e quebra qualquer `terraform import`.
      kubernetes_version = var.eks_versao
      instance_types     = [var.node_instance_type]
      min_size           = var.node_min
      max_size           = var.node_max
      desired_size       = var.node_min
      subnet_ids         = module.vpc.public_subnets
    }
  }

  # ⚠️ `enable_cluster_creator_admin_permissions` daria acesso apenas a QUEM
  # rodou o apply — que no CI é a role OIDC, não você. Resultado clássico:
  # `kubectl get pods` responde Unauthorized na sua máquina. Por isso os
  # acessos são declarados explicitamente, incluindo o usuário IAM local.
  enable_cluster_creator_admin_permissions = false

  access_entries = merge(
    {
      for apelido, arn in var.admin_principal_arns : apelido => {
        principal_arn = arn
        policy_associations = {
          admin = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    },
    {
      # O CD só implanta. Um pipeline comprometido não apaga o cluster.
      cd = {
        principal_arn = var.cd_role_arn
        policy_associations = {
          edit = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"
            access_scope = { type = "namespace", namespaces = [local.ns] }
          }
        }
      }

      # O `terraform plan` em PR deste repositório roda com uma role só de
      # leitura (ver bootstrap). O provider kubernetes precisa ler o namespace
      # no refresh, então ela entra aqui apenas com View.
      plan = {
        principal_arn = var.plan_role_arn
        policy_associations = {
          view = {
            policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
            access_scope = { type = "cluster" }
          }
        }
      }
    }
  )
}

# ── Namespace da aplicação ────────────────────────────────────────────────────
#
# ⏱️ Corte 16: sem ResourceQuota — ela existe para um ambiente não engolir o
# outro, e com um namespace só não protege de nada.
resource "kubernetes_namespace" "app" {
  metadata {
    name   = local.ns
    labels = { ambiente = var.ambiente }
  }
}
