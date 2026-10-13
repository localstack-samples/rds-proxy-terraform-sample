output "api_gateway_url" {
  value = aws_apigatewayv2_api.dog_api.api_endpoint
}

output "secret_proxy_endpoint" {
  value = aws_db_proxy.dogdb_secret_proxy.endpoint
}

output "iam_proxy_endpoint" {
  value = aws_db_proxy.dogdb_iam_proxy.endpoint
}
