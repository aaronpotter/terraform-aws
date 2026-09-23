terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.16.4"

  # No backend block on purpose. This config creates the bucket that the root
  # module's S3 backend writes to, so its own state has to stay local.
}
