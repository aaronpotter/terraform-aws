# Access for the kubernetes-deploy app (Helm chart deployed by GitHub Actions):
# - Pod Identity so its pods can read the RDS master password from Secrets Manager.
# - The app namespace, created here so the deploy role needs no cluster-scoped rights.
# - EKS access entries: deploy role (edit, app namespace only) and Terraform's own CI roles, which
#   need in-cluster access now that this module manages a Kubernetes object.
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
# Pod Identity: app pods read the DB master secret
# ------------------------------------------------------------------

resource "aws_eks_addon" "pod_identity_agent" {
  count = var.enabled ? 1 : 0

  cluster_name = aws_eks_cluster.main[0].name
  addon_name   = "eks-pod-identity-agent"

  # The agent runs as a DaemonSet, so it needs a node to land on.
  depends_on = [aws_eks_node_group.main]
}

resource "aws_iam_role" "app_db_secret" {
  name        = "${var.cluster_name}-${var.app_service_account}-db-secret"
  description = "Pod Identity role for ${var.app_namespace}/${var.app_service_account}: read the RDS master secret."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

# The secret uses the default aws/secretsmanager key, so no kms:Decrypt is needed.
resource "aws_iam_role_policy" "app_db_secret" {
  name = "read-db-master-secret"
  role = aws_iam_role.app_db_secret.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = aws_db_instance.main.master_user_secret[0].secret_arn
    }]
  })
}

resource "aws_eks_pod_identity_association" "app" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  namespace       = var.app_namespace
  service_account = var.app_service_account
  role_arn        = aws_iam_role.app_db_secret.arn
}

# ------------------------------------------------------------------
# App namespace
# ------------------------------------------------------------------

resource "kubernetes_namespace_v1" "app" {
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

# kubernetes-deploy's workflow: helm upgrade --install into the app namespace only. The "edit" policy
# covers Deployments, Services, ServiceAccounts, ConfigMaps and Secrets (Helm's release records), but
# not Roles/RoleBindings or anything cluster-scoped.
resource "aws_eks_access_entry" "deploy" {
  count = var.enabled ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = var.deploy_role_arn
}

resource "aws_eks_access_policy_association" "deploy" {
  count = var.enabled ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_eks_access_entry.deploy[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.app_namespace]
  }
}

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
