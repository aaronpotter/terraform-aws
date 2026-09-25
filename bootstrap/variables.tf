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

variable "lock_writer_arns" {
  description = "Extra principals allowed to take the state lock (run terraform plan locally) without being able to write state."
  type        = list(string)
  default     = ["arn:aws:iam::549610932637:user/apotter"]
}

variable "extra_state_writer_arns" {
  description = "Extra principals allowed to write state directly. Empty on purpose: humans write state through break-glass."
  type        = list(string)
  default     = []
}
