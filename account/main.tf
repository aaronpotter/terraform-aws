provider "aws" {
  region = var.region
}

data "aws_caller_identity" "current" {}

# Global sign-in events (console role switches) are delivered to EventBridge in us-east-1.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
