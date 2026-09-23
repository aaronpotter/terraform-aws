variable "state_bucket_name" {
  description = "Name of the S3 bucket holding Terraform state. Must match the bucket in the root module's backend block, and must be globally unique."
  type        = string
  default     = "apotter-tfstate-us-east-2"
}

variable "region" {
  description = "Region to create the state bucket in. Must match the region in the root module's backend block."
  type        = string
  default     = "us-east-2"
}
