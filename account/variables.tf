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
