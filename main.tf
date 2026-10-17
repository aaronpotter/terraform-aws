provider "aws" {
  region = "us-east-2"

  # Marks every resource as Terraform-managed, and says where its code lives.
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repo      = "aaronpotter/terraform-aws"
      Stack     = "root"
    }
  }
}

# The production VPC was deleted by hand on 2026-10-15 and removed from code. The root stack
# manages no resources now; the provider stays so Terraform can drop the old state entries.
