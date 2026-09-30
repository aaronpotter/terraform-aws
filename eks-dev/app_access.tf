# Shared cluster access for apps in the app namespace (currently the Security+ exam, see secplus.tf):
# - The Pod Identity agent add-on, so pods can read Secrets Manager without static keys.
# - The app namespace, created here so deploy roles need no cluster-scoped rights.
# - EKS access entries for Terraform's own CI roles, which need in-cluster access now that this
#   module manages a Kubernetes object.
# Everything tied to the cluster exists only while var.enabled is true.

locals {
  iam_prefix = "arn:aws:iam::${data.aws_caller_identity.current.account_id}"
}

data "aws_caller_identity" "current" {}

# Talks to the cluster as whoever runs Terraform (CI role or a local profile) via `aws eks get-token`.
# While the cluster is off, no resource uses this provider.
provider "kubernetes" {
  host                   = one(aws_eks_cluster.main[*].endpoint)
  cluster_ca_certificate = try(base64decode(aws_eks_cluster.main[0].certificate_authority[0].data), null)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", "us-east-2"]
  }
}

# ------------------------------------------------------------------
# Pod Identity agent (roles and associations are defined per app)
# ------------------------------------------------------------------

resource "aws_eks_addon" "pod_identity_agent" {
  count = var.enabled ? 1 : 0

  cluster_name = aws_eks_cluster.main[0].name
  addon_name   = "eks-pod-identity-agent"

  # The agent runs as a DaemonSet, so it needs a node to land on.
  depends_on = [aws_eks_node_group.main]
}

# ------------------------------------------------------------------
# App namespace
# ------------------------------------------------------------------

# The cluster was deleted outside Terraform, so the old address in state can't be refreshed (the
# kubernetes provider has nothing to connect to). Forget it without destroying, and manage the
# namespace under a new address on the recreated cluster.
removed {
  from = kubernetes_namespace_v1.app

  lifecycle {
    destroy = false
  }
}

resource "kubernetes_namespace_v1" "app_ns" {
  count = var.enabled ? 1 : 0

  metadata {
    name = var.app_namespace
  }

  # The CI roles' access entries must exist before Terraform can talk to the cluster.
  depends_on = [
    aws_eks_access_policy_association.ci_apply,
    aws_eks_access_policy_association.ci_plan,
    aws_eks_access_policy_association.admin,
  ]
}

# ------------------------------------------------------------------
# EKS access entries
# ------------------------------------------------------------------

# Terraform's apply role creates the namespace (cluster-scoped), so it needs cluster admin.
resource "aws_eks_access_entry" "ci_apply" {
  count = var.enabled ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = "${local.iam_prefix}:role/terraform-apply"
}

resource "aws_eks_access_policy_association" "ci_apply" {
  count = var.enabled ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_eks_access_entry.ci_apply[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# PR plans and nightly drift only read the namespace.
resource "aws_eks_access_entry" "ci_plan" {
  count = var.enabled ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = "${local.iam_prefix}:role/terraform-plan"
}

resource "aws_eks_access_policy_association" "ci_plan" {
  count = var.enabled ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_eks_access_entry.ci_plan[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}
