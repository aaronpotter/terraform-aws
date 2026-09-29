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

output "cloudfront_domain_name" {
  description = "Public URL for the app (https://<this>). The only way to reach it once the app enforces X-Origin-Verify."
  value       = aws_cloudfront_distribution.app.domain_name
}

output "origin_verify_secret_name" {
  description = "Secrets Manager secret with the raw X-Origin-Verify value; the app's chart reads it (originVerify.secretId)."
  value       = aws_secretsmanager_secret.origin_verify.name
}
