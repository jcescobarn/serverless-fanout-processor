output "frontend_website_endpoint" {
  description = "Endpoint del sitio web S3 (URL pública del frontend)"
  value       = aws_s3_bucket_website_configuration.frontend_website.website_endpoint
}