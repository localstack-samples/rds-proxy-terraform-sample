output "api_gateway_url" {
  value = aws_apigatewayv2_api.dog_api.api_endpoint
}
