terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# --- Network: use default VPC/subnet for simplicity ---
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# --- Security Group for EC2 ---
resource "aws_security_group" "app_sg" {
  name        = "pe-coding-test-app-sg"
  description = "Allow SSH and app port"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "App port"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = [var.allowed_app_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --- EC2 instance ---
data "aws_ami" "al2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.app_sg.id]
  key_name               = var.key_pair_name
  user_data = templatefile("${path.module}/user_data.sh", {
    sumo_installation_token = var.sumo_installation_token
    collector_name          = var.collector_name
  })
  tags = {
    Name = "pe-coding-test-ec2"
  }
}

# --- SNS topic ---
resource "aws_sns_topic" "alerts" {
  name = "slow-api-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# --- Package Lambda code ---
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../lambda_function/lambda_function.py"
  output_path = "${path.module}/lambda_function.zip"
}

# --- IAM role for Lambda ---
resource "aws_iam_role" "lambda_role" {
  name = "pe-coding-test-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "lambda.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

# Basic logging policy
resource "aws_iam_role_policy_attachment" "basic_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Least-privilege-ish policy:
# - DescribeInstances often needs "*"
# - Reboot/Start restricted to the specific instance ARN
# - sns:Publish restricted to topic ARN
resource "aws_iam_role_policy" "lambda_least_priv" {
  name = "pe-coding-test-lambda-least-priv"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid      = "DescribeInstances",
        Effect   = "Allow",
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus"],
        Resource = "*"
      },
      {
        Sid      = "RestartOnlyThisInstance",
        Effect   = "Allow",
        Action   = ["ec2:StopInstances", "ec2:RebootInstances", "ec2:StartInstances"],
        Resource = "arn:aws:ec2:${var.aws_region}:${data.aws_caller_identity.current.account_id}:instance/${aws_instance.app.id}"
      },
      {
        Sid      = "PublishOnlyThisTopic",
        Effect   = "Allow",
        Action   = ["sns:Publish"],
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}

# --- Lambda function ---
resource "aws_lambda_function" "sumo_checker" {
  function_name = "sumo-slow-api-checker"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SUMO_API_BASE    = var.sumo_api_base
      SUMO_ACCESS_ID   = var.sumo_access_id
      SUMO_ACCESS_KEY  = var.sumo_access_key
      SUMO_QUERY       = var.sumo_query
      LOOKBACK_MINUTES = tostring(var.lookback_minutes)

      INSTANCE_ID   = aws_instance.app.id
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn

      POLL_MAX_SECONDS  = "25"
      POLL_INTERVAL_SEC = "2"
    }
  }
}

# Optional: Lambda Function URL (handy if you later want Sumo webhook → Lambda)
resource "aws_lambda_function_url" "sumo_checker_url" {
  function_name      = aws_lambda_function.sumo_checker.function_name
  authorization_type = "NONE"
}

