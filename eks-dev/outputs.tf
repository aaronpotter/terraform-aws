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

output "secplus_db_secret_name" {
  description = "Secrets Manager secret (value set out-of-band) holding the Security+ exam's DB login; the chart's db.secretId."
  value       = aws_secretsmanager_secret.secplus_db_user.name
}

output "awsdevops_db_secret_name" {
  description = "Secrets Manager secret (value set out-of-band) holding the AWS DevOps exam's DB login; the chart's db.secretId."
  value       = aws_secretsmanager_secret.awsdevops_db_user.name
}
