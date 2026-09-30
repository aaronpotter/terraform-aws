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

output "secplus_certificate_validation_records" {
  description = "DNS records to create in Cloudflare (DNS only) so ACM can validate the Security+ exam certificate. Null when secplus_domain is unset."
  value = var.secplus_domain == "" ? null : [
    for d in aws_acm_certificate.secplus[0].domain_validation_options : {
      name  = d.resource_record_name
      type  = d.resource_record_type
      value = d.resource_record_value
    }
  ]
}
