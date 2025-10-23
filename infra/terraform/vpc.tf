module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.5"

  name = "bedrock-vpc"
  cidr = var.vpc_cidr

  azs             = ["${var.region}a","${var.region}b","${var.region}c"]
  public_subnets  = ["10.0.0.0/20","10.0.16.0/20","10.0.32.0/20"]
  private_subnets = ["10.0.48.0/20","10.0.64.0/20","10.0.80.0/20"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = { Project = "bedrock" }
}