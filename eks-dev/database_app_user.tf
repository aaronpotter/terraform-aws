# Credentials for a least-privilege PostgreSQL role, app_user, used by the kubernetes-deploy app in
# place of the master user. The chart's migration Job (running as the master user) creates the role
# and grants it DML from these values. Terraform only creates the secret.
#
# The password is ephemeral and written through a write-only attribute, so it never lands in
# Terraform state or this repo. To rotate it, bump app_db_user_secret_version and apply, then rerun
# the migration Job so the database role matches.

ephemeral "random_password" "app_db_user" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "app_db_user" {
  name        = "${var.cluster_name}-postgres-app-user"
  description = "Least-privilege PostgreSQL login (app_user) for ${var.app_namespace}/${var.app_service_account}."
}

resource "aws_secretsmanager_secret_version" "app_db_user" {
  secret_id = aws_secretsmanager_secret.app_db_user.id

  secret_string_wo = jsonencode({
    username = "app_user"
    password = ephemeral.random_password.app_db_user.result
  })
  secret_string_wo_version = var.app_db_user_secret_version
}
