output "unzip_function_arn" {
  description = "ARN of the s3-trigger-unzip Lambda function."
  value       = aws_lambda_function.unzip.arn
}

output "unzip_buckets" {
  description = "Input, output, and scripts bucket names."
  value       = { for k, b in aws_s3_bucket.unzip : k => b.id }
}

output "secplus_repository_url" {
  description = "ECR repository URL for the Security+ exam image."
  value       = aws_ecr_repository.security_plus_exam.repository_url
}

output "secplus_deploy_role_arn" {
  description = "Role the Security+ exam repo assumes to deploy; pass to eks-dev as secplus_deploy_role_arn."
  value       = one(aws_iam_role.secplus_deploy[*].arn)
}

output "secplus_ecr_push_role_arn" {
  description = "Role the Security+ exam build job assumes to push images."
  value       = one(aws_iam_role.secplus_ecr_push[*].arn)
}

output "secplus_cloudfront_domain_name" {
  description = "Public URL for the Security+ exam (https://<this>). Null until secplus_origin_domain is set."
  value       = one(aws_cloudfront_distribution.secplus[*].domain_name)
}

output "secplus_origin_verify_secret_name" {
  description = "Secrets Manager secret with the raw X-Origin-Verify value for the Security+ exam."
  value       = aws_secretsmanager_secret.secplus_origin_verify.name
}

output "awsdevops_repository_url" {
  description = "ECR repository URL for the AWS DevOps exam image."
  value       = aws_ecr_repository.aws_devops_exam.repository_url
}

output "awsdevops_deploy_role_arn" {
  description = "Role the AWS DevOps exam repo assumes to deploy; pass to eks-dev as awsdevops_deploy_role_arn."
  value       = one(aws_iam_role.awsdevops_deploy[*].arn)
}

output "awsdevops_ecr_push_role_arn" {
  description = "Role the AWS DevOps exam build job assumes to push images."
  value       = one(aws_iam_role.awsdevops_ecr_push[*].arn)
}

output "awsdevops_cloudfront_domain_name" {
  description = "CloudFront domain for the AWS DevOps exam; the Cloudflare CNAME target for awsdevops_domain. Null until awsdevops_origin_domain is set."
  value       = one(aws_cloudfront_distribution.awsdevops[*].domain_name)
}

output "awsdevops_origin_verify_secret_name" {
  description = "Secrets Manager secret with the raw X-Origin-Verify value for the AWS DevOps exam; the chart's originVerify.secretId."
  value       = aws_secretsmanager_secret.awsdevops_origin_verify.name
}

output "turbocerts_home_bucket" {
  description = "S3 bucket holding the turbocerts.com landing page; the turbocerts-home repo's S3_BUCKET variable."
  value       = aws_s3_bucket.turbocerts_home.id
}

output "turbocerts_apex_distribution_id" {
  description = "ID of the apex (turbocerts.com) CloudFront distribution; the turbocerts-home repo's CLOUDFRONT_DISTRIBUTION_ID variable."
  value       = aws_cloudfront_distribution.secplus_apex.id
}

output "turbocerts_home_deploy_role_arn" {
  description = "Role the turbocerts-home repo assumes to deploy."
  value       = one(aws_iam_role.turbocerts_home_deploy[*].arn)
}
