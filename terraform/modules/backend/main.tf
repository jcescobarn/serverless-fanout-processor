resource "aws_s3_bucket" "invoice_bucket" {
  bucket = "invoice-bucket-${data.aws_caller_identify.current.account_id}"
}

resource "aws_s3_bucket_cors" "invoice_bucket_cors" {
  bucket = aws_s3_bucket.invoice_bucket.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"] # En producción, sería tu dominio de frontend
  }
}

resource "aws_dynamodb_table" "invoice_results" {
  name           = "InvoiceAuditResults"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "invoiceId"

  attribute {
    name = "invoiceId"
    type = "S"
  }
}

resource "aws_sagemaker_notebook_instance" "ml_notebook" {
  name          = "InvoiceFraudTrainer"
  instance_type = "ml.t3.medium" # Tipo permitido por el lab
  role_arn      = data.aws_iam_role.lab_role.arn
  
  tags = {
    Project = "invoice-fraud-detector"
  }
}

resource "aws_lambda_function" "upload_service" {
  function_name    = "upload-service"
  filename         = "../../src-upload-service.zip"
  source_code_hash = filebase64sha256("../../src-upload-service.zip")
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  role             = data.aws_iam_role.lab_role.arn

  environment {
    variables = {
      INVOICE_BUCKET_NAME = aws_s3_bucket.invoice_bucket.bucket
    }
  }
}

resource "aws_lambda_function" "process_service" {
  function_name    = "process-service"
  filename         = "../../src-process-service.zip"
  source_code_hash = filebase64sha256("../../src-process-service.zip")
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.10"
  role             = data.aws_iam_role.lab_role.arn
  timeout          = 120 # Textract y SageMaker pueden tardar

  environment {
    variables = {
      INVOICE_BUCKET_NAME     = aws_s3_bucket.invoice_bucket.bucket
      DB_TABLE_NAME           = aws_dynamodb_table.invoice_results.name
      SAGEMAKER_ENDPOINT_NAME = data.aws_ssm_parameter.sagemaker_endpoint_name.value
    }
  }
}

resource "aws_api_gateway_rest_api" "api" {
  name = "Invoice-API"
}

# Endpoint: /get-upload-url (para Lambda 1)
resource "aws_api_gateway_resource" "upload_url" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "get-upload-url"
}
resource "aws_api_gateway_method" "upload_url_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.upload_url.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "upload_url_int" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.upload_url.id
  http_method             = aws_api_gateway_method.upload_url_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.upload_service.invoke_arn
}

# Endpoint: /process-invoice (para Lambda 2)
resource "aws_api_gateway_resource" "process" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "process-invoice"
}
resource "aws_api_gateway_method" "process_post" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.process.id
  http_method   = "POST"
  authorization = "NONE"
}
resource "aws_api_gateway_integration" "process_int" {
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.process.id
  http_method             = aws_api_gateway_method.process_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.process_service.invoke_arn
}

# --- Configuración de CORS, permisos y despliegue de API ---
module "cors" {
  source          = "squidfunk/api-gateway-enable-cors/aws"
  version         = "0.3.3"
  api_id          = aws_api_gateway_rest_api.api.id
  api_resource_id = aws_api_gateway_rest_api.api.root_resource_id # CORS en la raíz
}


# Lambda permissions for API Gateway
resource "aws_lambda_permission" "allow_api_upload" {
  statement_id  = "AllowAPIGatewayInvokeUpload"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_api_process" {
  statement_id  = "AllowAPIGatewayInvokeProcess"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_service.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*"
}

# API Gateway deployment and stage
resource "aws_api_gateway_deployment" "api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.upload_url.id,
      aws_api_gateway_resource.process.id
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = "prod"
}