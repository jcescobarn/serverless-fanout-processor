variable "aws_region" {
  description = "aws region"
  type        = string
  default     = "us-east-1"
}

variable "s3_frontend_bucket_name" {
  description = "bucket name"
  type        = string
}