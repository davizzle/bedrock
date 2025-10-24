terraform {
  backend "s3" {
    bucket         = "bedrock-tfstate-120217955965-us-east-1"
    key            = "eks/bedrock.tfstate"
    region         = "us-east-1"
    dynamodb_table = "bedrock-tflock"
    encrypt        = true
  }
}
