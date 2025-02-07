#########################################
#               NETWORKING              #
#########################################

resource "aws_vpc" "dog_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "dog-vpc"
  }
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.dog_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.dog_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-subnet-2"
  }
}

resource "aws_db_subnet_group" "rds_subnet_group" {
  name       = "rds-subnet-group"
  subnet_ids = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id,
  ]

  tags = {
    Name = "RDS Subnet Group"
  }
}

#########################################
#            SECURITY GROUPS            #
#########################################

resource "aws_security_group" "rds_proxy_sg" {
  vpc_id = aws_vpc.dog_vpc.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda_sg.id]
    cidr_blocks = ["10.0.2.0/24", "10.0.3.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-proxy-sg"
  }
}

resource "aws_security_group" "lambda_sg" {
  vpc_id = aws_vpc.dog_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "lambda-sg"
  }
}

#########################################
#               SECRETS                 #
#########################################

# Secret #1
resource "aws_secretsmanager_secret" "super_secret" {
  name = "super-secret"

  tags = {
    Name = "super-secret"
  }
}

resource "aws_secretsmanager_secret_version" "super_secret_value" {
  secret_id     = aws_secretsmanager_secret.super_secret.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

# Secret #2
resource "aws_secretsmanager_secret" "iam_secret" {
  name = "iam_secret"

  tags = {
    Name = "iam_secret"
  }
}

resource "aws_secretsmanager_secret_version" "iam_secret_value" {
  secret_id     = aws_secretsmanager_secret.iam_secret.id
  secret_string = jsonencode({
    username = var.iam_username
    password = var.iam_password
  })
}

#########################################
#         RDS & RDS PROXY SETUP         #
#########################################

resource "aws_iam_role" "rds_monitoring_role" {
  name = "rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring_attachment" {
  role       = aws_iam_role.rds_monitoring_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster" "dogdb" {
  cluster_identifier                  = "dogdb-cluster"
  engine                              = "aurora-postgresql"
  engine_version                      = "15.3"
  database_name                       = var.db_name
  master_username                     = var.db_username
  master_password                     = var.db_password
  skip_final_snapshot                 = true
  vpc_security_group_ids              = [aws_security_group.rds_proxy_sg.id]
  db_subnet_group_name                = aws_db_subnet_group.rds_subnet_group.name
  iam_roles                           = [aws_iam_role.rds_monitoring_role.arn]
  apply_immediately                   = true
  enable_http_endpoint                = true
  iam_database_authentication_enabled = true
}

resource "aws_rds_cluster_instance" "dogdb_instance" {
  identifier         = "dogdb-instance"
  cluster_identifier = aws_rds_cluster.dogdb.id
  instance_class     = "db.t3.medium"
  engine             = "aurora-postgresql"
}

# RDS Proxy with username and password authentication enabled

resource "aws_db_proxy" "dogdb_secret_proxy" {
  name                   = "dogdb-secret-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_security_group_ids = [aws_security_group.rds_proxy_sg.id]
  vpc_subnet_ids         = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id,
  ]
  require_tls = true

  auth {
    description = "RDS Proxy Secret Auth"
    iam_auth    = "DISABLED"
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.super_secret.arn
  }

  depends_on = [
    aws_rds_cluster.dogdb,
    aws_rds_cluster_instance.dogdb_instance,
  ]
}

resource "aws_db_proxy_default_target_group" "secret_proxy_target_group" {
  db_proxy_name = aws_db_proxy.dogdb_secret_proxy.name
}

resource "aws_db_proxy_target" "secret_proxy_target" {
  db_proxy_name         = aws_db_proxy.dogdb_secret_proxy.name
  target_group_name     = aws_db_proxy_default_target_group.secret_proxy_target_group.name
  db_cluster_identifier = aws_rds_cluster.dogdb.id

  lifecycle {
    create_before_destroy = true
  }
}


resource "aws_db_proxy_default_target_group" "iam_proxy_target_group" {
  db_proxy_name = aws_db_proxy.dogdb_iam_proxy.name
}

resource "aws_db_proxy_target" "iam_proxy_target" {
  db_proxy_name         = aws_db_proxy.dogdb_iam_proxy.name
  target_group_name     = aws_db_proxy_default_target_group.iam_proxy_target_group.name
  db_cluster_identifier = aws_rds_cluster.dogdb.id

  lifecycle {
    create_before_destroy = true
  }
}

# RDS Proxy with IAM authentication enabled

resource "aws_db_proxy" "dogdb_iam_proxy" {
  name                   = "dogdb-iam-proxy"
  engine_family          = "POSTGRESQL"
  role_arn               = aws_iam_role.rds_proxy_role.arn
  vpc_security_group_ids = [aws_security_group.rds_proxy_sg.id]
  vpc_subnet_ids         = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id,
  ]
  require_tls = true

  auth {
    description = "RDS Proxy Auth"
    iam_auth    = "REQUIRED"
    secret_arn  = aws_secretsmanager_secret.iam_secret.arn
  }

  depends_on = [
    aws_rds_cluster.dogdb,
    aws_rds_cluster_instance.dogdb_instance,
  ]
}

#########################################
#         IAM ROLES & POLICIES          #
#########################################


resource "aws_iam_role" "rds_proxy_role" {
  name = "rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "rds.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "rds_proxy_policy" {
  name = "rds-proxy-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = aws_secretsmanager_secret.super_secret.arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_proxy_role_attach" {
  role       = aws_iam_role.rds_proxy_role.name
  policy_arn = aws_iam_policy.rds_proxy_policy.arn
}


resource "aws_iam_role" "lambda_role" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Action    = "sts:AssumeRole",
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_policy" "lambda_ec2_policy" {
  name        = "lambda-ec2-policy"
  description = "Allows Lambda to manage network interfaces for VPC access"
  policy      = jsonencode({
    Version   = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = [
        "ec2:CreateNetworkInterface",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DeleteNetworkInterface"
      ],
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_ec2_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_ec2_policy.arn
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "lambda-policy-rds"
  description = "Allows Lambda to interact with RDS Proxy and Secrets Manager"
  policy      = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["rds-db:connect"],
        Resource = "arn:aws:rds-db:${var.aws_region}:${var.aws_account_id}:dbuser:${aws_db_proxy.dogdb_iam_proxy.name}/*"
      },
      {
        Effect = "Allow",
        Action = [
          "rds-data:ExecuteStatement",
          "rds-data:BatchExecuteStatement"
        ],
        Resource = aws_rds_cluster.dogdb.arn
      },
      {
        Effect   = "Allow",
        Action   = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Resource = "arn:aws:secretsmanager:us-east-1:*:secret:dogdb-secret-*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_iam_policy" "lambda_rds_proxy_policy" {
  name        = "lambda-rds-proxy-policy"
  description = "Allows Lambda to connect to RDS Proxy"
  policy      = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = "sts:AssumeRole",
        Resource = "arn:aws:iam::*:role/lambda-execution-role"
      },
      {
        Effect   = "Allow",
        Action   = "rds:GenerateDbAuthToken",
        Resource = aws_rds_cluster.dogdb.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_rds_proxy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_rds_proxy_policy.arn
}

# Instead of a custom logging policy, attach AWSLambdaBasicExecutionRole.
resource "aws_iam_role_policy_attachment" "apigw_logging_attachment" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_cloudwatch_log_group" "lambda_log_group" {
  name              = "/aws/lambda/put-dog"
  retention_in_days = 7
}


#########################################
#           LAMBDA FUNCTIONS            #
#########################################

resource "aws_lambda_function" "get_dog" {
  function_name = "get-dog"
  runtime       = "java21"
  role          = aws_iam_role.lambda_role.arn
  handler       = "cloud.localstack.getdog.GetDogHandler"
  filename      = "../api-lambdas/get-dog-lambda/target/get-dog-lambda-1.0.0.jar"

  vpc_config {
    subnet_ids         = [
      aws_subnet.private_subnet_1.id,
      aws_subnet.private_subnet_2.id,
    ]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      SECRET_ARN     = aws_secretsmanager_secret.super_secret.arn
      DATABASE_NAME  = var.db_name
      DB_CLUSTER_ARN = aws_rds_cluster.dogdb.arn
    }
  }
}

resource "aws_lambda_function" "post_dog" {
  function_name = "post-dog"
  runtime       = "java21"
  role          = aws_iam_role.lambda_role.arn
  handler       = "cloud.localstack.postdog.AddDogHandler"
  filename      = "../api-lambdas/post-dog-lambda/target/post-dog-lambda-1.0.0.jar"
  timeout       = 15
  memory_size   = 512

  vpc_config {
    subnet_ids         = [
      aws_subnet.private_subnet_1.id,
      aws_subnet.private_subnet_2.id,
    ]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      HOST          = aws_db_proxy.dogdb_secret_proxy.endpoint
      DATABASE_NAME = var.db_name
      DB_USER     = var.db_username
      USER_PASSWORD = var.db_password
    }
  }
}

resource "aws_lambda_function" "put_dog" {
  function_name = "put-dog"
  runtime       = "java21"
  role          = aws_iam_role.lambda_role.arn
  handler       = "cloud.localstack.putdog.UpdateDogHandler"
  filename      = "../api-lambdas/put-dog-lambda/target/put-dog-lambda-1.0.0.jar"
  timeout       = 15
  memory_size   = 512

  vpc_config {
    subnet_ids         = [
      aws_subnet.private_subnet_1.id,
      aws_subnet.private_subnet_2.id,
    ]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      HOST          = aws_db_proxy.dogdb_iam_proxy.endpoint
      DATABASE_NAME = var.db_name
      DB_USER     = var.iam_username
      AWS_REGION    = var.aws_region
    }
  }
}

resource "aws_lambda_function" "delete_dog" {
  function_name = "delete-dog"
  runtime       = "java21"
  role          = aws_iam_role.lambda_role.arn
  handler       = "cloud.localstack.deletedog.DeleteDogHandler"
  filename      = "../api-lambdas/delete-dog-lambda/target/delete-dog-lambda-1.0.0.jar"

  vpc_config {
    subnet_ids         = [
      aws_subnet.private_subnet_1.id,
      aws_subnet.private_subnet_2.id,
    ]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      HOST          = aws_db_proxy.dogdb_secret_proxy.endpoint
      SECRET_ARN    = aws_secretsmanager_secret.super_secret.arn
      AWS_REGION    = var.aws_region
      DATABASE_NAME = var.db_name
    }
  }

}

#########################################
#              API GATEWAY              #
#########################################

resource "aws_apigatewayv2_api" "dog_api" {
  name          = "DogAPI"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "default_stage" {
  api_id      = aws_apigatewayv2_api.dog_api.id
  name        = "dev"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.lambda_log_group.arn
    format          = "$context.requestId $context.status $context.error.message"
  }
}

resource "aws_apigatewayv2_integration" "post_dog_integration" {
  api_id           = aws_apigatewayv2_api.dog_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.post_dog.invoke_arn
}

resource "aws_apigatewayv2_route" "post_dog_route" {
  api_id    = aws_apigatewayv2_api.dog_api.id
  route_key = "POST /dogs"
  target    = "integrations/${aws_apigatewayv2_integration.post_dog_integration.id}"
}

resource "aws_apigatewayv2_integration" "put_dog_integration" {
  api_id           = aws_apigatewayv2_api.dog_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.put_dog.invoke_arn
}

resource "aws_apigatewayv2_route" "put_dog_route" {
  api_id    = aws_apigatewayv2_api.dog_api.id
  route_key = "PUT /dogs"
  target    = "integrations/${aws_apigatewayv2_integration.put_dog_integration.id}"
}

resource "aws_apigatewayv2_integration" "delete_dog_integration" {
  api_id           = aws_apigatewayv2_api.dog_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.delete_dog.invoke_arn
}

resource "aws_apigatewayv2_route" "delete_dog_route" {
  api_id    = aws_apigatewayv2_api.dog_api.id
  route_key = "DELETE /dogs/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.delete_dog_integration.id}"
}

resource "aws_apigatewayv2_integration" "get_dog_integration" {
  api_id           = aws_apigatewayv2_api.dog_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.get_dog.invoke_arn
}

resource "aws_apigatewayv2_route" "get_dog_route" {
  api_id    = aws_apigatewayv2_api.dog_api.id
  route_key = "GET /dogs/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.get_dog_integration.id}"
}

#########################################
#          DATABASE INITIALIZATION      #
#########################################

resource "aws_lambda_function" "db-setup" {
  function_name = "db-setup"
  runtime       = "java21"
  role          = aws_iam_role.lambda_role.arn
  handler       = "cloud.localstack.initdb.InitDBHandler"
  filename      = "../api-lambdas/db-setup-lambda/target/db-setup-lambda-1.0.0.jar"

  vpc_config {
    subnet_ids         = [
      aws_subnet.private_subnet_1.id,
      aws_subnet.private_subnet_2.id,
    ]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      AWS_REGION         = var.aws_region
      DB_SECRET_ARN      = aws_secretsmanager_secret.super_secret.arn
      RDS_PROXY_ENDPOINT = aws_db_proxy.dogdb_secret_proxy.endpoint
      DB_NAME            = var.db_name
    }
  }
}

# resource "null_resource" "trigger_lambda" {
#   depends_on = [
#     aws_lambda_function.db-setup,
#     aws_rds_cluster.dogdb,
#   ]
#
#   provisioner "local-exec" {
#     command = "awslocal lambda invoke --function-name db-setup --region us-east-1 output.json"
#   }
# }
