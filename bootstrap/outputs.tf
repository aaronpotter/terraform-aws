output "state_bucket_name" {
  description = "Bucket name to put in the root module's backend block."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_region" {
  description = "Region to put in the root module's backend block."
  value       = aws_s3_bucket.tfstate.region
}
