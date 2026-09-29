output "unzip_function_arn" {
  description = "ARN of the s3-trigger-unzip Lambda function."
  value       = aws_lambda_function.unzip.arn
}

output "unzip_buckets" {
  description = "Input, output, and scripts bucket names."
  value       = { for k, b in aws_s3_bucket.unzip : k => b.id }
}

output "hello_world_repository_url" {
  description = "ECR repository URL for docker push."
  value       = aws_ecr_repository.hello_world.repository_url
}

output "github_deploy_role_arn" {
  description = "Role the kubernetes-deploy repo assumes via OIDC."
  value       = aws_iam_role.github_deploy.arn
}

output "github_ecr_push_role_arn" {
  description = "Role the kubernetes-deploy build job assumes to push to hello-world."
  value       = aws_iam_role.github_ecr_push.arn
}
