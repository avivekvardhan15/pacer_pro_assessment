variable "aws_region" {
  type    = string
  default = "us-east-2"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_pair_name" {
  type        = string
  description = "EC2 key pair name for SSH (must already exist in the region)"
}

variable "allowed_ssh_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "allowed_app_cidr" {
  type    = string
  default = "0.0.0.0/0"
}

variable "sns_email" {
  type        = string
  description = "Email to subscribe to SNS topic (confirm subscription email)"
}

# --- Optional: secure the webhook call to Lambda Function URL ---
variable "webhook_token" {
  type        = string
  description = "If set, Lambda requires header X-Webhook-Token to match"
  default     = ""
  sensitive   = true
}

# Tuning for stop/start wait loops
variable "wait_max_seconds" {
  type    = number
  default = 900
}

variable "wait_interval_sec" {
  type    = number
  default = 10
}

# Optional: if you still want Sumo collector bootstrap on EC2
variable "sumo_installation_token" {
  type      = string
  sensitive = true
  default   = ""
}

variable "collector_name" {
  type    = string
  default = "sampleapp-ec2-collector"
}

variable "sumo_api_base" {
  type        = string
  description = "Sumo Logic API base URL"
  default     = "https://api.sumologic.com"
}

variable "sumo_access_id" {
  type        = string
  description = "Sumo Logic access id"
  sensitive   = true
}

variable "sumo_access_key" {
  type        = string
  description = "Sumo Logic access key"
  sensitive   = true
}

variable "sumo_query" {
  type        = string
  description = "Sumo query to run"
}

variable "lookback_minutes" {
  type        = number
  description = "Lookback window for query"
  default     = 15
}
