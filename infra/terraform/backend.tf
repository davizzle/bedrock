terraform {
  backend "s3" {
    bucket         = "bedrock-tfstate-YOUR_ACCOUNT_ID-us-east-1"
    key            = "eks/bedrock.tfstate"
    region         = "us-east-1"
    dynamodb_table = "bedrock-tflock"
    encrypt        = true
  }
}
