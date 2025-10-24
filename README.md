Project Bedrock — EKS + Retail Store Sample App

This repo provisions an EKS cluster on AWS with Terraform, and deploys the AWS Retail Store Sample App (with in-cluster MySQL/Postgres/DynamoDB Local/RabbitMQ/Redis) via GitHub Actions (OIDC). It also sets up a read-only developer IAM user and Kubernetes RBAC.

✅ Outcome: a running microservices demo app reachable at a public ELB URL, plus secure read-only cluster access for developers.

Contents

Architecture
