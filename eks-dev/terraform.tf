terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.16.4"

  # Single-environment module, so the key lives here rather than in a -backend-config file.
  backend "s3" {
    bucket       = "apotter-tfstate-us-east-2"
    key          = "environments/eks-dev/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
