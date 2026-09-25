terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.16.4"

  # No default key: init must be given -backend-config=environments/<env>/backend.tfvars,
  # so a bare `terraform init` can't silently pick a state.
  backend "s3" {
    bucket       = "apotter-tfstate-us-east-2"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
