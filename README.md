# terraform-aws

A single EC2 instance per environment in its own VPC, plus an on-demand EKS dev cluster (`eks-dev/`), with Terraform state in S3.

## First-time setup

The state bucket is created by `bootstrap/`, which keeps its own state locally.

```sh
cd bootstrap
terraform init
terraform apply        # creates apotter-tfstate-us-east-2

cd ..
terraform init         # uses the S3 backend in terraform.tf
terraform apply -var ssh_cidr=<your-ip>/32
```

The bucket name and region in `bootstrap/variables.tf` must match the `backend "s3"` block in `terraform.tf`.

## Dev EKS cluster (`eks-dev/`)

A managed EKS cluster named `apotterlab`: one on-demand t3.small node in public subnets of its own VPC (10.2.0.0/16). It is a separate root module with its own state key (`environments/eks-dev/terraform.tfstate`) and its own workflow, `.github/workflows/terraform-eks-dev.yaml`.

**Node size:** this AWS account is on the Free plan, which only launches free-tier-eligible instance types. Any other type fails with `InvalidParameterCombination`, and the node group sits in `CREATING` until Terraform times out. t3.small (2 GiB, up to 11 pods, 4 of them used by system pods) is the smallest workable choice. For more headroom, `c7i-flex.large` (4 GiB, 29 pods) is also eligible.

**Cost:** about $3.10/day (~$93/month) while it exists, mostly the $0.10/hr EKS control plane. On the Free plan that comes out of your credits, and AWS closes the account when they run out unless you upgrade to a paid plan. Destroy the cluster when you're not using it.

### Locally

```sh
cd eks-dev
export TF_VAR_admin_cidr=<your-ip>/32   # who can reach the API endpoint; never committed
terraform init
terraform apply                          # ~15 minutes
aws eks update-kubeconfig --region us-east-2 --name apotterlab
kubectl get nodes

terraform destroy                        # when done
```

### CI

PRs and pushes to `main` that touch `eks-dev/` only run a plan. To create, change, or remove the cluster, run the **Terraform EKS Dev Cluster** workflow manually and pick `apply` or `destroy`.

One-time setup: create a GitHub Environment named `eks-dev` with secrets `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` and a variable `ADMIN_CIDR` (e.g. `203.0.113.4/32`). Don't add required reviewers to it, because they would also block PR plans.

### Kubernetes version

`kubernetes_version` defaults to `null`, which creates the cluster on the current EKS default version. Terraform won't upgrade it later on its own. To upgrade, set `kubernetes_version` one minor version higher and apply. A cluster left running past its end of standard support moves to extended-support pricing ($0.60/hr), so for this disposable cluster, destroying and recreating it is usually simpler.

### Provider lock file

CI runs on linux_amd64. After changing provider versions, refresh the hashes for both platforms:

```sh
terraform providers lock -platform=darwin_arm64 -platform=linux_amd64
```

## Account guardrails (`account/`)

Account-level controls: currently the CloudTrail trail (`account-trail`, all regions, log file validation) and its log bucket `apotter-cloudtrail-549610932637`. It's a separate root module with state key `account/terraform.tfstate`.

**CI never applies this module**, and `terraform.yaml` ignores `account/**`. A human applies it after review, so a merged PR can't weaken the guardrails:

```sh
cd account
terraform init
terraform plan -out=account.tfplan
terraform apply account.tfplan
```
