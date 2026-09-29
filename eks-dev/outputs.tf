output "cluster_name" {
  description = "Name of the EKS cluster, or null when var.enabled is false."
  value       = one(aws_eks_cluster.main[*].name)
}

output "cluster_endpoint" {
  description = "URL of the EKS API server, or null when var.enabled is false."
  value       = one(aws_eks_cluster.main[*].endpoint)
}

output "cluster_version" {
  description = "Kubernetes version the control plane is running, or null when var.enabled is false."
  value       = one(aws_eks_cluster.main[*].version)
}

output "configure_kubectl" {
  description = "Command that writes this cluster into your kubeconfig."
  value       = var.enabled ? "aws eks update-kubeconfig --region us-east-2 --name ${var.cluster_name}" : "Cluster is disabled; set enabled = true in terraform.tfvars and apply."
}

output "db_endpoint" {
  description = "PostgreSQL host, reachable only from inside the cluster."
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "PostgreSQL port."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.main.db_name
}

output "db_master_secret_arn" {
  description = "Secrets Manager secret holding the master username and password."
  value       = one(aws_db_instance.main.master_user_secret[*].secret_arn)
}

output "app_db_secret_role_arn" {
  description = "Pod Identity role mapped to the app's ServiceAccount; can read the app_user DB secret only."
  value       = aws_iam_role.app_db_secret.arn
}

output "app_db_user_secret_name" {
  description = "Secrets Manager secret with the app_user credentials ({\"username\",\"password\"})."
  value       = aws_secretsmanager_secret.app_db_user.name
}

output "app_db_user_secret_arn" {
  description = "ARN of the app_user credentials secret."
  value       = aws_secretsmanager_secret.app_db_user.arn
}

output "app_migrate_db_secret_role_arn" {
  description = "Pod Identity role for the migration ServiceAccount; reads the master and app_user secrets."
  value       = aws_iam_role.app_migrate_db_secret.arn
}
