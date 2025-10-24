# Assumes you already have these in your repo:
# data "aws_eks_cluster" "this" { name = module.eks.cluster_name }
# data "aws_eks_cluster_auth" "this" { name = module.eks.cluster_name }
# provider "kubernetes" { host=..., cluster_ca_certificate=..., token=... }

resource "kubernetes_cluster_role" "readonly_with_logs" {
  metadata { name = "readonly-with-logs" }
  rule {
    api_groups = [""]
    resources  = ["pods", "pods/log", "services", "endpoints", "namespaces", "configmaps", "events"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "eks_viewers_readonly" {
  metadata { name = "eks-viewers-readonly" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.readonly_with_logs.metadata[0].name
  }
  subject {
    kind      = "Group"
    name      = "eks-viewers"
    api_group = "rbac.authorization.k8s.io"
  }
}
