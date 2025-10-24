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

  enable_irsa = true

  eks_managed_node_groups = {
    default = {
      instance_types = ["t3.medium"]
      desired_size   = 3
      min_size       = 2
      max_size       = 5
    }
  }

  # Use merge() so CICD entry is added only when cicd_role_arn is set
access_entries = merge(
  var.cicd_role_arn == null ? {} : {
    cicd = {
      principal_arn = var.cicd_role_arn
      policy_associations = {
        admin = {
          policy_arn  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  },
  var.admin_principal_arn == null ? {} : {
    admin = {
      principal_arn = var.admin_principal_arn
      policy_associations = {
        admin = {
          policy_arn  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  },
  {
    dev_readonly = {
      principal_arn     = local.dev_user_arn
      kubernetes_groups = ["eks-viewers"]  # not a reserved system: group
      policy_associations = {
        view = {
          policy_arn  = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }
)

  tags = { Project = "bedrock" }
}

#---- Kubernetes provider (for RBAC) ----
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
