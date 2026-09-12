# API Gateway HTTP API — a borda pública do sistema (F3-3.4).
#
# Este repositório cria a API, o stage e os logs. As ROTAS e o authorizer
# vivem no oficina-lambda-auth: rota depende de integração e de authorizer ao
# mesmo tempo, e o authorizer é uma Lambda. Deixar as rotas aqui obrigaria a
# aplicar este repo duas vezes na primeira subida — a "costura assimétrica"
# que o backlog descreve. Com as rotas do lado do authorizer, a ordem vira
# uma linha reta: infra-k8s → infra-db → app → lambda-auth.

resource "aws_apigatewayv2_api" "principal" {
  name          = "${var.projeto}-${var.ambiente}"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"] # sem front conhecido; restringir quando houver
    allow_methods = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type", "x-signature", "x-correlation-id"]
    max_age       = 300
  }
}

resource "aws_cloudwatch_log_group" "apigw" {
  name              = "/aws/apigw/${var.projeto}-${var.ambiente}"
  retention_in_days = 14 # sem isto o log fica para sempre e vira custo
}

resource "aws_apigatewayv2_stage" "principal" {
  api_id      = aws_apigatewayv2_api.principal.id
  name        = "$default" # sem prefixo de stage na URL
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn

    # JSON estruturado: casa com o requisito de logs com correlação, e é o
    # que permite cruzar uma requisição da borda até o log do pod.
    #
    # ⚠️ Duas armadilhas. Um nome de variável de $context ESCRITO ERRADO não
    # dá erro nenhum: vira string vazia no log, e você só descobre no meio de
    # um incidente. Já uma variável INEXISTENTE derruba o apply — foi o caso
    # de $context.request.header.x-correlation-id, que o backlog sugeria e o
    # HTTP API não suporta em access log (só em parameter mapping). A
    # correlação com o cliente fica com o middleware da aplicação (F3-4.1).
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      latency        = "$context.responseLatency"
      integrationErr = "$context.integration.error"
      authorizerErr  = "$context.authorizer.error"
    })
  }

  default_route_settings {
    throttling_burst_limit   = 200
    throttling_rate_limit    = 100
    detailed_metrics_enabled = true
  }
}

# ── Segredo compartilhado ───────────────────────────────────────────────────
# O segredo já existe: foi criado por scripts/prod-secret.sh no dia 3, no
# formato {"jwt_secret": ..., "webhook_secret": ...}. Publicamos o ARN para o
# lambda-auth encontrá-lo sem saber o nome.
data "aws_secretsmanager_secret" "app" {
  name = "oficina/${var.ambiente}/app"
}

resource "aws_ssm_parameter" "jwt_secret_arn" {
  name  = "/oficina/${var.ambiente}/jwt/secret_arn"
  type  = "String"
  value = data.aws_secretsmanager_secret.app.arn
}

resource "aws_ssm_parameter" "apigw_id" {
  name  = "/oficina/${var.ambiente}/apigw/id"
  type  = "String"
  value = aws_apigatewayv2_api.principal.id
}

resource "aws_ssm_parameter" "apigw_url" {
  name  = "/oficina/${var.ambiente}/apigw/url"
  type  = "String"
  value = aws_apigatewayv2_stage.principal.invoke_url
}
