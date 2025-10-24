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

variable "dev_readonly_iam_user_arn" {
  type    = string
  default = "" # fill later
}

variable "cicd_role_arn" {
  type        = string
  description = "IAM role ARN that GitHub Actions (OIDC) will assume for Terraform and kubectl"
  default     = null
}

variable "admin_principal_arn" {
  type        = string
  default     = null
  description = "IAM user/role ARN to grant EKS admin access"
}