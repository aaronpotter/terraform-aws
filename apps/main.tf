provider "aws" {
  region = "us-east-2"

  # Marks every resource as Terraform-managed, and says where its code lives.
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repo      = "aaronpotter/terraform-aws"
      Stack     = "apps"
    }
  }
}

# CloudFront only accepts ACM certificates issued in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repo      = "aaronpotter/terraform-aws"
      Stack     = "apps"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}
