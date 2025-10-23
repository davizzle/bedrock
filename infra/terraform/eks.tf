locals {
  dev_user_arn = aws_iam_user.dev_readonly.arn
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.9"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true  # needed later for AWS Load Balancer Controller

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      desired_size   = 3
      min_size       = 2
      max_size       = 5
    }
  }

  # NEW: Grant read-only via EKS Access Entries (no aws-auth here)
  access_entries = {
    dev_readonly = {
      principal_arn = local.dev_user_arn
      kubernetes_groups = ["eks-viewers"] 
      # Attach AWS-managed read-only policy at cluster scope
      policy_associations = {
        view = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = { type = "cluster" } # or: { type = "namespace", namespaces = ["default"] }
        }
      }
    }
  }


  tags = { Project = "bedrock" }
}

# Kubernetes provider (so we can create RBAC after cluster exists)
data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name
}
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

# Create a cluster-wide read-only binding for the "eks-viewers" group
resource "kubernetes_cluster_role_binding" "viewer" {
  metadata { name = "eks-viewers-view" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "view"
  }
  subject {
    kind      = "Group"
    name      = "eks-viewers"
    api_group = "rbac.authorization.k8s.io"
  }
}