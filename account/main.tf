provider "aws" {
  region = var.region

  # Marks every resource as Terraform-managed, and says where its code lives.
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repo      = "aaronpotter/terraform-aws"
      Stack     = "account"
    }
  }
}

data "aws_caller_identity" "current" {}

# Global sign-in events (console role switches) are delivered to EventBridge in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  # Marks every resource as Terraform-managed, and says where its code lives.
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repo      = "aaronpotter/terraform-aws"
      Stack     = "account"
    }
  }
}
