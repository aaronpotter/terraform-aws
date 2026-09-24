output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "URL of the EKS API server."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_version" {
  description = "Kubernetes version the control plane is running."
  value       = aws_eks_cluster.main.version
}

output "configure_kubectl" {
  description = "Command that writes this cluster into your kubeconfig."
  value       = "aws eks update-kubeconfig --region us-east-2 --name ${aws_eks_cluster.main.name}"
}
