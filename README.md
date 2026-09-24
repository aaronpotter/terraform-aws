# terraform-aws

A single EC2 instance in an existing VPC, with Terraform state in S3.

## First-time setup

The state bucket is created by `bootstrap/`, which keeps its own state locally.

```sh
cd bootstrap
terraform init
terraform apply        # creates tfstate bucket

cd ..
terraform init         # uses the S3 backend in terraform.tf
terraform apply -var ssh_cidr=<your-ip>/32
```

The bucket name and region in `bootstrap/variables.tf` must match the `backend "s3"` block in `terraform.tf`.
