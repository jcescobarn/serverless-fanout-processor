output "api_gateway_invoke_url" {
  description = "URL de invocación para la API de Facturas"
  value       = aws_api_gateway_stage.prod.invoke_url
}

output "sagemaker_notebook_name" {
  description = "Nombre de la instancia de Notebook para entrenar el modelo"
  value       = aws_sagemaker_notebook_instance.ml_notebook.name
}