output "trail_arn" {
  description = "ARN of the account CloudTrail trail."
  value       = aws_cloudtrail.account.arn
}

output "trail_bucket" {
  description = "S3 bucket holding CloudTrail log files."
  value       = aws_s3_bucket.trail.id
}
