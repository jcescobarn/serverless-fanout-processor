data "aws_iam_role" "lab_role" {
  name = "labRole"
}

data "aws_ssm_parameters" "sagemaker_endpoint_name" {
  name = "/invoice-fraud/sagemaker-endpoint"
  default = "none"
}

data "aws_caller_identity" "current" {}