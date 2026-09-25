variable "region" {
  description = "Home region for account-level resources. The trail is multi-region regardless."
  type        = string
  default     = "us-east-2"
}

variable "trail_name" {
  description = "Name of the account CloudTrail trail."
  type        = string
  default     = "account-trail"
}

variable "trail_log_retention_days" {
  description = "Days to keep CloudTrail log files before they expire."
  type        = number
  default     = 365
}

variable "state_bucket_name" {
  description = "Terraform state bucket (created by bootstrap/)."
  type        = string
  default     = "apotter-tfstate-us-east-2"
}

variable "github_owner" {
  description = "GitHub repository owner, as it appears in the OIDC subject claim."
  type        = string
  default     = "aaronpotter"
}

variable "github_owner_id" {
  description = "Numeric GitHub owner ID, part of the immutable OIDC subject claim."
  type        = string
  default     = "9371584"
}

variable "github_repo" {
  description = "GitHub repository name, as it appears in the OIDC subject claim."
  type        = string
  default     = "terraform-aws"
}

variable "github_repo_id" {
  description = "Numeric GitHub repository ID, part of the immutable OIDC subject claim."
  type        = string
  default     = "1340975248"
}
