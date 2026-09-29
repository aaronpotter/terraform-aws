# Credentials for a least-privilege PostgreSQL role, app_user, used by the kubernetes-deploy app in
# place of the master user. The chart's migration Job (running as the master user) creates the role
# and grants it DML from these values.
#
# Terraform manages the secret but NOT its value: refreshing a secret *version* calls
# GetSecretValue, which the read-only CI plan role (terraform-plan) can't and shouldn't do. The value
# was set once (40 random alphanumeric characters) and is rotated outside Terraform; see README.

resource "aws_secretsmanager_secret" "app_db_user" {
  name        = "${var.cluster_name}-postgres-app-user"
  description = "Least-privilege PostgreSQL login (app_user) for ${var.app_namespace}/${var.app_service_account}."
}

# The version that first set the value was managed here. Forget it without deleting it, so the
# current password stays in place and plans no longer need to read it.
removed {
  from = aws_secretsmanager_secret_version.app_db_user

  lifecycle {
    destroy = false
  }
}

# ------------------------------------------------------------------
# Migration ServiceAccount: the only identity that should hold the master password
# ------------------------------------------------------------------
# The chart's migration hook Job runs as production/hello-world-migrate (the chart creates that
# ServiceAccount). It reads the master secret to connect, and the app_user secret to create the role.
# Once the app runs as app_user from its own ServiceAccount, the app role drops the master secret.

resource "aws_iam_role" "app_migrate_db_secret" {
  name        = "${var.cluster_name}-${var.app_migrate_service_account}-db-secret"
  description = "Pod Identity role for ${var.app_namespace}/${var.app_migrate_service_account}: read the master and app_user secrets."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pods.eks.amazonaws.com" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "app_migrate_db_secret" {
  name = "read-db-master-and-app-user-secrets"
  role = aws_iam_role.app_migrate_db_secret.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "secretsmanager:GetSecretValue"
      Resource = [
        aws_db_instance.main.master_user_secret[0].secret_arn,
        aws_secretsmanager_secret.app_db_user.arn,
      ]
    }]
  })
}

resource "aws_eks_pod_identity_association" "app_migrate" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.main[0].name
  namespace       = var.app_namespace
  service_account = var.app_migrate_service_account
  role_arn        = aws_iam_role.app_migrate_db_secret.arn
}
