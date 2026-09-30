# Access for the Security+ exam app (Node.js + PostgreSQL), a second Helm release in app_namespace.
# Same model as app_access.tf / database_app_user.tf, with its own database, DB role, secrets and
# roles, so it shares nothing with hello-world except the RDS instance and the namespace.
#
# Bootstrapping inside PostgreSQL is not Terraform's job (RDS is private): the chart's migration Job,
# running as the master user, creates database "securityplus" and role "securityplus_user" from the
# secret below, then applies the schema.

# ------------------------------------------------------------------
# DB login for the app: least-privilege role, own database
# ------------------------------------------------------------------
# Terraform manages the secret but NOT its value (the read-only plan role
# can't read secret values). Set it once, JSON with keys username, password, host, dbname, port:
#   aws secretsmanager put-secret-value --secret-id apotterlab-postgres-securityplus-user \
#     --secret-string file://secret.json     # password: 40 random alphanumeric characters

resource "aws_secretsmanager_secret" "secplus_db_user" {
  name        = "${var.cluster_name}-postgres-securityplus-user"
  description = "Least-privilege PostgreSQL login (securityplus_user, database securityplus) for ${var.app_namespace}/${var.secplus_service_account}."
}

# ------------------------------------------------------------------
# Pod Identity: app pods
# ------------------------------------------------------------------

resource "aws_iam_role" "secplus_app" {
  name        = "${var.cluster_name}-${var.secplus_service_account}-secrets"
  description = "Pod Identity role for ${var.app_namespace}/${var.secplus_service_account}: read its own DB login and origin-verify secrets."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "secplus_app" {
  name = "read-app-secrets"
  role = aws_iam_role.secplus_app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = [
        aws_secretsmanager_secret.secplus_db_user.arn,
        # Created in apps/ (secplus.tf); matched by pattern to avoid a cross-stack dependency.
        "arn:aws:secretsmanager:us-east-2:${data.aws_caller_identity.current.account_id}:secret:apotterlab-secplus-origin-verify-??????",
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "secplus_app" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  namespace       = var.app_namespace
  service_account = var.secplus_service_account
  role_arn        = aws_iam_role.secplus_app.arn
}

# ------------------------------------------------------------------
# Pod Identity: migration Job (the only identity here that reads the master password)
# ------------------------------------------------------------------

resource "aws_iam_role" "secplus_migrate" {
  name        = "${var.cluster_name}-${var.secplus_migrate_service_account}-db-secret"
  description = "Pod Identity role for ${var.app_namespace}/${var.secplus_migrate_service_account}: read the master and securityplus_user secrets."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "secplus_migrate" {
  name = "read-db-master-and-app-secrets"
  role = aws_iam_role.secplus_migrate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = [
        aws_db_instance.main.master_user_secret[0].secret_arn,
        aws_secretsmanager_secret.secplus_db_user.arn,
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "secplus_migrate" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  namespace       = var.app_namespace
  service_account = var.secplus_migrate_service_account
  role_arn        = aws_iam_role.secplus_migrate.arn
}

# ------------------------------------------------------------------
# Deploy access: edit in the app namespace only (same as the kubernetes-deploy role)
# ------------------------------------------------------------------

resource "aws_eks_access_entry" "secplus_deploy" {
  count = var.enabled && var.secplus_deploy_role_arn != null ? 1 : 0

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = var.secplus_deploy_role_arn
}

resource "aws_eks_access_policy_association" "secplus_deploy" {
  count = length(aws_eks_access_entry.secplus_deploy)

  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = aws_eks_access_entry.secplus_deploy[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSEditPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.app_namespace]
  }
}
