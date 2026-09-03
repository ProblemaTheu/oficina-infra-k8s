output "vpc_id" {
  description = "ID da VPC"
  value       = module.vpc.vpc_id
}

output "subnets_privadas" {
  description = "Subnets privadas — usadas pelo RDS (oficina-infra-db)"
  value       = module.vpc.private_subnets
}

output "cluster_name" {
  description = "Nome do cluster (aws eks update-kubeconfig --name)"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do EKS"
  value       = module.eks.cluster_endpoint
}

output "node_security_group_id" {
  description = "SG dos nós — origem liberada na porta 5432 do RDS"
  value       = module.eks.node_security_group_id
}

output "lambda_security_group_id" {
  description = "SG das Lambdas na VPC"
  value       = aws_security_group.lambda.id
}

output "namespace" {
  description = "Namespace da aplicação"
  value       = kubernetes_namespace.app.metadata[0].name
}

output "kubeconfig" {
  description = "Comando para configurar o kubectl"
  value       = "aws eks update-kubeconfig --region ${var.regiao} --name ${module.eks.cluster_name}"
}
