terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.16.4"

  # Account-level guardrails. Applied only by a human (break-glass once it exists), never by CI.
  backend "s3" {
    bucket       = "apotter-tfstate-us-east-2"
    key          = "account/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
