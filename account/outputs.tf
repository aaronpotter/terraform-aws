output "trail_arn" {
  description = "ARN of the account CloudTrail trail."
  value       = aws_cloudtrail.account.arn
}

output "trail_bucket" {
  description = "S3 bucket holding CloudTrail log files."
  value       = aws_s3_bucket.trail.id
}

output "terraform_plan_role_arn" {
  description = "Set as AWS_ROLE_ARN in the production-plan and eks-dev GitHub environments."
  value       = aws_iam_role.terraform_plan.arn
}

output "terraform_apply_role_arn" {
  description = "Set as AWS_ROLE_ARN in the production and eks-dev-apply GitHub environments."
  value       = aws_iam_role.terraform_apply.arn
}

output "github_oidc_provider_arn" {
  description = "IAM OIDC provider for GitHub Actions."
  value       = aws_iam_openid_connect_provider.github.arn
}
