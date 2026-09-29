terraform {
  required_providers {
    # 6.x here (the other modules stay on 5.x): 5.x rejects the python3.14 Lambda runtime.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  required_version = ">= 1.16.4"

  # Applied by CI (terraform-apps.yaml) through the production environments, like the root module.
  backend "s3" {
    bucket       = "apotter-tfstate-us-east-2"
    key          = "environments/apps/terraform.tfstate"
    region       = "us-east-2"
    encrypt      = true
    use_lockfile = true
  }
}
