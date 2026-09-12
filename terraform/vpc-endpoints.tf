# Consequência direta do corte 2 (sem NAT Gateway).
#
# A Lambda auth-token precisa estar na VPC para alcançar o RDS, que é
# privado. Mas ENI de Lambda NUNCA recebe IP público — nem em subnet
# pública — então, sem NAT, ela não alcança nenhum serviço da AWS pela
# internet, inclusive o Secrets Manager de onde lê o segredo do JWT.
#
# Um endpoint de interface resolve sem trazer o NAT de volta: US$ 0,01/h por
# AZ contra US$ 0,045/h do NAT, e o tráfego não sai da rede da AWS.
#
# A alternativa seria injetar o segredo como variável de ambiente da função.
# Sai de graça, mas coloca o segredo em texto legível para qualquer um com
# lambda:GetFunctionConfiguration — e o código já lê do Secrets Manager.

resource "aws_security_group" "vpce" {
  name        = "${var.projeto}-vpce"
  description = "Endpoints de interface da VPC"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "HTTPS das Lambdas"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.regiao}.secretsmanager"
  vpc_endpoint_type = "Interface"

  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpce.id]

  # Com DNS privado, secretsmanager.us-east-1.amazonaws.com resolve para o
  # endpoint dentro da VPC — o SDK funciona sem nenhuma configuração.
  private_dns_enabled = true
}
