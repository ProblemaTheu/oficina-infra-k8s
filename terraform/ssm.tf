# Contrato com os outros repositórios. A SSM é a fronteira entre os states:
# nenhum repo lê o state do outro, todos leem parâmetros nomeados.

resource "aws_ssm_parameter" "vpc_id" {
  name  = "/oficina/shared/vpc/id"
  type  = "String"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "subnets_privadas" {
  name  = "/oficina/shared/vpc/subnets_privadas"
  type  = "StringList"
  value = join(",", module.vpc.private_subnets)
}

resource "aws_ssm_parameter" "subnets_publicas" {
  name  = "/oficina/shared/vpc/subnets_publicas"
  type  = "StringList"
  value = join(",", module.vpc.public_subnets)
}

resource "aws_ssm_parameter" "lambda_sg" {
  name  = "/oficina/shared/lambda/sg_id"
  type  = "String"
  value = aws_security_group.lambda.id
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "/oficina/shared/eks/cluster_name"
  type  = "String"
  value = module.eks.cluster_name
}

resource "aws_ssm_parameter" "node_sg" {
  name  = "/oficina/shared/eks/node_sg_id"
  type  = "String"
  value = module.eks.node_security_group_id
}

resource "aws_ssm_parameter" "namespace" {
  name  = "/oficina/${var.ambiente}/k8s/namespace"
  type  = "String"
  value = kubernetes_namespace.app.metadata[0].name
}
