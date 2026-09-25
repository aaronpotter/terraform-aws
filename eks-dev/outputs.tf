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
