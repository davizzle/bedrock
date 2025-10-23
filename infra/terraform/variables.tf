variable "region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "bedrock-eks"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "dev_readonly_iam_user_arn" {
  type    = string
  default = "" # fill later
}