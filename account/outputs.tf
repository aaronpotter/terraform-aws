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

output "break_glass_role_arn" {
  description = "Role to assume in an emergency (MFA required). Use as role_arn in the break-glass CLI profile."
  value       = aws_iam_role.break_glass.arn
}

output "break_glass_alert_topics" {
  description = "SNS topics that email break-glass alerts. Each subscription needs its confirmation email clicked once."
  value       = [module.break_glass_alert_us_east_1.topic_arn, module.break_glass_alert_home.topic_arn]
}

output "engineers_group" {
  description = "Read-only group for humans. Membership is changed by hand (see README)."
  value       = aws_iam_group.engineers.name
}
