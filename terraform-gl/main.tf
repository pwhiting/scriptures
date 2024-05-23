provider "aws" {
  region = "us-east-1"
}

resource "aws_secretsmanager_secret" "search_api_secret" {
  name = "gl-search-api-secret"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "gl-lambda_exec_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  inline_policy {
    name = "gl-secretsmanager_policy"
    policy = jsonencode({
      Version = "2012-10-17",
      Statement = [
        {
          Action = [
            "secretsmanager:GetSecretValue"
          ],
          Effect = "Allow",
          Resource = aws_secretsmanager_secret.search_api_secret.arn
        }
      ]
    })
  }
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}


data "archive_file" "search" {
  type        = "zip"
  source_file = "${path.module}/search.py"
  output_path = "${path.module}/search.zip"
}

resource "aws_lambda_function" "search_function" {
  filename         = data.archive_file.search.output_path
  function_name    = "gl-search_function"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "search.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  layers           = ["arn:aws:lambda:us-east-1:534284445277:layer:openai-pinecone:1"]
  architectures    = ["x86_64"]
  source_code_hash = filebase64sha256(data.archive_file.search.output_path)
  environment {
    variables = {
      SECRET_NAME = aws_secretsmanager_secret.search_api_secret.name
    }
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.search_function.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_api_gateway_rest_api" "api" {
  name        = "gl-search-api"
  description = "API for search functionality"
}

resource "aws_api_gateway_resource" "search" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "search"
}

resource "aws_api_gateway_method" "search_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.search.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.search.id
  http_method = aws_api_gateway_method.search_post.http_method
  type        = "AWS_PROXY"
  integration_http_method = "POST"
  uri         = aws_lambda_function.search_function.invoke_arn
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [aws_api_gateway_integration.lambda]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "dev"
}

resource "aws_api_gateway_api_key" "api_key" {
  name    = "gl-search-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "gl-search-api-usage-plan"
  api_stages {
    api_id = aws_api_gateway_rest_api.api.id
    stage  = aws_api_gateway_deployment.deployment.stage_name
  }
}

resource "aws_api_gateway_usage_plan_key" "usage_plan_key" {
  key_id        = aws_api_gateway_api_key.api_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.usage_plan.id
}

output "api_url" {
  value = aws_api_gateway_deployment.deployment.invoke_url
}

output "api_key" {
  sensitive = true
  value = aws_api_gateway_api_key.api_key.value
}


