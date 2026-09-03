#!/usr/bin/env bash
# Derruba a plataforma. Rode DEPOIS do destroy.sh do oficina-infra-db —
# o security group do RDS referencia o SG dos nós, e o Terraform de lá lê
# a rede daqui pela SSM.
#
#   ~/git/oficina-infra-db/destroy.sh && ~/git/oficina-infra-k8s/destroy.sh
set -euo pipefail

REGIAO=${REGIAO:-us-east-1}
CLUSTER=${CLUSTER:-oficina}
NS=${NS:-oficina-prod}
cd "$(dirname "$0")/terraform"

# 1. O NLB é criado pelo Kubernetes, não pelo Terraform. Se ele ficar de pé,
#    o destroy da VPC falha ("DependencyViolation") e você paga um load
#    balancer órfão sem perceber. Apagar o Service é o que o remove.
if aws eks describe-cluster --name "$CLUSTER" --region "$REGIAO" >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGIAO" >/dev/null
  echo "==> Removendo Services do tipo LoadBalancer em $NS"
  kubectl delete svc --all -n "$NS" --ignore-not-found --timeout=5m || true
  echo "==> Aguardando a AWS apagar o load balancer (~60 s)"
  sleep 60
fi

# 2. O namespace some junto com o cluster; removê-lo do state antes evita o
#    destroy travar tentando falar com uma API que já não existe.
terraform state rm kubernetes_namespace.app 2>/dev/null || true

echo "==> terraform destroy (~15 min)"
terraform destroy -auto-approve

# 3. Conferência: nada além do bucket de state e das roles do bootstrap.
echo "==> Órfãos (o esperado é tudo vazio):"
aws elbv2 describe-load-balancers --region "$REGIAO" --query 'LoadBalancers[].LoadBalancerName' --output text
aws ec2 describe-vpcs --region "$REGIAO" --filters Name=tag:Projeto,Values=oficina --query 'Vpcs[].VpcId' --output text
aws rds describe-db-instances --region "$REGIAO" --query 'DBInstances[].DBInstanceIdentifier' --output text

# A chave KMS do EKS não some no destroy: ela entra em PendingDeletion e leva
# no mínimo 7 dias para sumir de verdade, cobrando ~US$ 1/mês até lá (~US$ 0,23
# nos 7 dias). Nada a fazer além de saber que existe — a AWS não permite
# encurtar a janela.
echo "==> Chaves KMS aguardando exclusão (cobram ate sumirem):"
aws kms list-keys --region "$REGIAO" --query 'Keys[].KeyId' --output text | tr '\t' '\n' | while read -r k; do
  [ -z "$k" ] && continue
  estado=$(aws kms describe-key --key-id "$k" --region "$REGIAO" --query 'KeyMetadata.KeyState' --output text 2>/dev/null)
  [ "$estado" = "PendingDeletion" ] && echo "  $k"
done
