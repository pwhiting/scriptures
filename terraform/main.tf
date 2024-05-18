provider "aws" {
  region = "us-east-1"
}

resource "aws_secretsmanager_secret" "search_api_secret" {
  name = "search-api-secret"
}

resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"
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
    name = "secretsmanager_policy"
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

resource "null_resource" "create_layer_zip2" {
  provisioner "local-exec" {
    command = <<EOT
        mkdir -p layer/python
        pip3 install --platform manylinux2014_x86_64 \
           --target=layer/python \
           --implementation cp \
           --python-version 3.12 \
           --only-binary=:all: \
           --upgrade openai pinecone-client 
    EOT
  }
}


resource "null_resource" "create_layer_zip" {
  provisioner "local-exec" {
    command = <<EOT
      echo "Starting layer creation..."
      if [ ! -f layer/python ]; then
        mkdir -p layer/python
        echo "Installing packages..."
        pip3 install --platform manylinux2014_x86_64 \
           --target=layer/python \
           --implementation cp \
           --python-version 3.12 \
           --only-binary=:all: \
           --upgrade openai pinecone-client
        echo "Packages installed."
      else
        echo "Layer already exists."
      fi
      echo "Layer creation complete."
    EOT
  }
}


data "archive_file" "layer" {
  type        = "zip"
  source_dir  = "${path.module}/layer"
  output_path = "${path.module}/python-library.zip"
  depends_on  = [null_resource.create_layer_zip]
}

resource "aws_lambda_layer_version" "python-library" {
  filename                  = "${path.module}/python-library.zip"
  layer_name                = "pinecone-openai"
  compatible_runtimes       = ["python3.12"]
  compatible_architectures  = ["x86_64"]
  source_code_hash          = data.archive_file.layer.output_base64sha256
#  source_code_hash          = filebase64sha256(data.archive_file.layer.output_path)
}

data "archive_file" "search" {
  type        = "zip"
  #source_file = "${path.module}/code/search.py"
  source_dir  = "${path.module}/code"
  output_path = "${path.module}/search.zip"
}

resource "aws_lambda_function" "search_function" {
  filename         = data.archive_file.search.output_path
  function_name    = "search_function"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "search.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  layers           = [aws_lambda_layer_version.python-library.arn]
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
  name        = "search-api"
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
  stage_name  = "prod"
}

resource "aws_api_gateway_api_key" "api_key" {
  name    = "search-api-key"
  enabled = true
}

resource "aws_api_gateway_usage_plan" "usage_plan" {
  name = "search-api-usage-plan"

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
  value = "${aws_api_gateway_rest_api.api.execution_arn}/prod/search"
}

output "api_key" {
  sensitive = true
  value = aws_api_gateway_api_key.api_key.value
}


