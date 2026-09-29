# terraform-aws

A production EC2 lab instance in its own VPC, plus an on-demand EKS dev cluster (`eks-dev/`), with Terraform state in S3.

## First-time setup

The state bucket is created by `bootstrap/`, which keeps its own state locally.

```sh
cd bootstrap
terraform init
terraform apply        # creates tfstate bucket

cd ..
terraform init -backend-config=environments/production/backend.tfvars
terraform plan -var-file=environments/production/terraform.tfvars -var ssh_cidr=<your-ip>/32
```

The bucket name and region in `bootstrap/variables.tf` must match the `backend "s3"` block in `terraform.tf`. That block has no default `key`, so `terraform init` must always be given an environment's `backend.tfvars`.

Production is the only environment for the root module. CI applies it when changes merge to `main`. PR and manual runs only plan it, using the unprotected `production-plan` GitHub environment. The apply uses `production`, which requires approval and only deploys from `main`. `production-plan` sets `AWS_ROLE_ARN` to `terraform-plan`, and `production` sets it to `terraform-apply`.

## Changes go through PRs

`main` is protected by a ruleset: every change needs a pull request, and the `Main Plan` and `EKS Dev Plan` checks must pass. Each workflow's `Detect Changes` job skips its plan when the PR doesn't touch that workflow's files. A skipped plan still counts as passing, so docs-only PRs aren't blocked.


## Resource tags

Every module's AWS provider sets `default_tags`, so every taggable resource carries `ManagedBy = terraform`, `Repo = aaronpotter/terraform-aws`, and `Stack` (`root`, `eks-dev`, `account`, or `bootstrap`). If you find a tagged resource in the console, change it in code, not by hand, or the nightly drift check will flag it (for `root` and `eks-dev`).
=======
## State bucket protection (`bootstrap/`)

The state bucket's policy limits writes even for account admins. `aws:PrincipalArn` is checked against these lists:

| Action | Allowed for |
|---|---|
| Write or delete `*.tfstate` | `terraform-apply` (CI), `break-glass-admin`, root |
| Take or release the lock (`*.tflock`) | those three, plus `terraform-plan` and `user/apotter`, so a local `plan` works |
| Delete object versions (the state history) | `break-glass-admin`, root |
| Delete the bucket, or change its policy, versioning, lifecycle, encryption, or public access block | `break-glass-admin`, root |

So a local `terraform apply` of `account/` or `eks-dev/` needs break-glass (see "Local credentials"). CI applies are unaffected. Root can always remove a bad bucket policy.

`bootstrap/` keeps its own state locally (`bootstrap/terraform.tfstate`, git-ignored) because it creates the bucket. Applying it after this policy is in place also needs break-glass, since only `break-glass-admin` can change the bucket policy.


## Dev EKS cluster (`eks-dev/`)

A managed EKS cluster named `apotterlab`: one on-demand t3.small node in public subnets of its own VPC (10.2.0.0/16). It is a separate root module with its own state key (`environments/eks-dev/terraform.tfstate`) and its own workflow, `.github/workflows/terraform-eks-dev.yaml`.

**Node size:** this AWS account is on the Free plan, which only launches free-tier-eligible instance types. Any other type fails with `InvalidParameterCombination`, and the node group sits in `CREATING` until Terraform times out. t3.small (2 GiB, up to 11 pods, 4 of them used by system pods) is the smallest workable choice. For more headroom, `c7i-flex.large` (4 GiB, 29 pods) is also eligible.

**Cost:** about $3.10/day (~$93/month) while it exists, mostly the $0.10/hr EKS control plane. On the Free plan that comes out of your credits, and AWS closes the account when they run out unless you upgrade to a paid plan. Set `enabled = false` when you're not using it.

### PostgreSQL (`eks-dev/database.tf`)

An RDS PostgreSQL 18 database (`apotterlab-postgres`, `db.t4g.micro`, 20 GiB gp3, encrypted) in two private subnets of the apotterlab VPC (`10.2.11.0/24`, `10.2.12.0/24`, with no route to the internet). Only the EKS cluster security group can reach port 5432, so nodes and pods can connect and nothing outside the cluster can.

- **It doesn't depend on `enabled`.** Turning the cluster off keeps the database and its data. While the cluster is off, nothing can connect.
- **Deletion protection is on**, and destroying it still takes a final snapshot (`apotterlab-postgres-final`). It has **1 day** of automated backups, the Free plan's maximum (anything higher fails with `FreeTierRestrictionError`), and is single-AZ.
- **Password:** RDS generates the master password and keeps it in Secrets Manager (`terraform output db_master_secret_arn`). It never appears in state or in this repo. **RDS rotates it every 7 days by default**, so a password copied into a Kubernetes Secret stops working after the next rotation. For anything long-lived, have the app read the secret at runtime (with EKS Pod Identity), or sync it with External Secrets Operator.
- **Free plan:** only `db.t3.micro` and `db.t4g.micro` are allowed for PostgreSQL, and backups are capped at 1 day. Upgrading the account plan removes both limits.

For a quick test from inside the cluster:

```sh
SECRET=$(terraform -chdir=eks-dev output -raw db_master_secret_arn)
HOST=$(terraform -chdir=eks-dev output -raw db_endpoint)
PASS=$(aws secretsmanager get-secret-value --secret-id "$SECRET" --query SecretString --output text | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')
kubectl run psql --rm -it --restart=Never --image=postgres:18 --env=PGPASSWORD="$PASS" -- psql -h "$HOST" -U postgres -d app -c 'select version();'
```

### App access (`eks-dev/app_access.tf`)

Access for the `kubernetes-deploy` repo's app, a Helm chart deployed by GitHub Actions. Everything tied to the cluster exists only while `enabled = true`.

| Piece | Details |
|---|---|
| Namespace `production` | Created by Terraform through the `kubernetes` provider, so the deploy role needs no cluster-scoped rights. The workflow must **not** pass `--create-namespace`. |
| Pod Identity | The `eks-pod-identity-agent` addon, plus role `apotterlab-hello-world-db-secret` (trusted by `pods.eks.amazonaws.com`, `secretsmanager:GetSecretValue` on the RDS master secret and the app_user secret only), associated with ServiceAccount `production/hello-world`. The chart creates the ServiceAccount. |
| App database login | Secret `apotterlab-postgres-app-user` holds `{"username":"app_user","password":…}` for a least-privilege role that the chart's migration Job creates. The password is **ephemeral** and written through `secret_string_wo`, so it never appears in Terraform state or this repo. To rotate it, bump `app_db_user_secret_version`, apply, then rerun the migration Job. The Pod Identity role can read this secret and the master secret. |
| Migration identity | Role `apotterlab-hello-world-migrate-db-secret`, associated with ServiceAccount `production/hello-world-migrate` (created by the chart's migration hook). It reads the master and app_user secrets to create `app_user`. Once the app runs as `app_user`, the app role drops the master secret, leaving the migration Job as the only identity that holds it. |
| Access entry `github-actions-deploy` | `AmazonEKSEditPolicy` scoped to the `production` namespace: Deployments, Services, ServiceAccounts, ConfigMaps and Secrets (Helm's release records). It can't create Roles/RoleBindings or cluster-scoped objects. |
| Access entries for Terraform's CI roles | `terraform-apply` gets cluster admin, which creating the namespace needs. `terraform-plan` gets `AmazonEKSViewPolicy`, which PR plans and nightly drift use to read it. |

The `kubernetes` provider authenticates with `aws eks get-token` as whoever runs Terraform, so a local plan or apply needs the `aws` CLI and an identity with an access entry.

### Locally

```sh
cd eks-dev
terraform init
terraform apply                          # ~15 minutes
aws eks update-kubeconfig --region us-east-2 --name apotterlab
kubectl get nodes
```

### Turning the cluster off and on

`enabled` in `eks-dev/terraform.tfvars` is the switch. Set it to `false` and apply to remove the cluster, node group, and access entries, which stops the ~$3.10/day. The VPC, subnets, and IAM roles stay (they're free), so setting it back to `true` recreates the cluster in about 15 minutes.

`terraform destroy` is blocked on purpose: the VPC has `prevent_destroy`, so a stray destroy can't take down the whole module. If you really want to remove everything, delete that `lifecycle` block in a reviewed change first.

### CI

PRs and pushes to `main` that touch `eks-dev/` only run a plan. To make a merged change take effect, including turning the cluster on or off with `enabled`, run the **Terraform EKS Dev Cluster** workflow manually **from `main`** and pick `apply`. The apply job uses the `eks-dev-apply` environment, which only deploys from `main`, so an apply started from a branch is refused.

One-time setup: two GitHub Environments. There are no AWS secrets: each job assumes the role in its environment's `AWS_ROLE_ARN` variable through GitHub OIDC (see `account/`).
- `eks-dev`, used by the plan job. `AWS_ROLE_ARN` is the `terraform-plan` role. Leave it open to all branches and don't add required reviewers, because PR plans run on `refs/pull/*` and would be blocked.
- `eks-dev-apply`, used by the apply job. `AWS_ROLE_ARN` is the `terraform-apply` role. Set its deployment branch policy to `main` only, because that policy is what keeps the admin role on `main`.

### Kubernetes version

`kubernetes_version` defaults to `null`, which creates the cluster on the current EKS default version. Terraform won't upgrade it later on its own. To upgrade, set `kubernetes_version` one minor version higher and apply. A cluster left running past its end of standard support moves to extended-support pricing ($0.60/hr), so for this disposable cluster, turning it off and on again with `enabled` is usually simpler.

### Provider lock file

CI runs on linux_amd64. After changing provider versions, refresh the hashes for both platforms:

```sh
terraform providers lock -platform=darwin_arm64 -platform=linux_amd64
```

## Apps (`apps/`)

Resources that were first created by hand, and brought under Terraform with `import` blocks. The blocks were removed once the import was applied. State key: `environments/apps/terraform.tfstate`.

| Resource | Notes |
|---|---|
| Lambda `s3-trigger-unzip` (Python 3.14) + role `lambda-s3-trigger-role` + policy `s3-trigger` + log group | A `.gz` object in `apotter-lambda-input` is decompressed into `apotter-lambda-output`, then deleted from the input bucket. **The code lives in `apps/lambda/s3-trigger-unzip/`** and deploys through Terraform. |
| Buckets `apotter-lambda-input`, `-output`, `-scripts` | SSE-S3, public access blocked, ACLs disabled. The input bucket's `.gz` object-created notification triggers the Lambda. |
| ECR `hello-world` | Immutable tags, scan on push. A lifecycle policy keeps the 20 newest **tagged** images. Untagged images stay, because they're the manifests inside multi-arch indexes like `latest`. The `kubernetes-deploy` repo pushes images here. |
| Role `github-actions-ecr-push` | Build job for `kubernetes-deploy`, trusted only for `ref:refs/heads/main`. It can push to and read `hello-world` only (plus `ecr:GetAuthorizationToken`). |
| Role `github-actions-deploy` | OIDC role for `aaronpotter/kubernetes-deploy`: `AmazonEC2ContainerRegistryPowerUser` + `eks:DescribeCluster`, plus namespace-scoped edit in the cluster (see eks-dev "App access"). Trust is pinned to that repo's IDs and exactly two subjects: `ref:refs/heads/main` (build-push) and `environment:production` (deploy). |

**CI** (`terraform-apps.yaml`): same flow as the root module. `Apps Plan` runs on PRs with the read-only role in `production-plan`. On merge, `Terraform Apply - Apps` waits for approval in `production`. The Lambda zip is built during plan and uploaded with the saved plan, so the apply deploys exactly what was planned. Drift detection covers this stack too.

This module uses **AWS provider 6.x**. The other modules are on 5.x, which rejects the `python3.14` runtime.

**Known issues, left as they were imported:**
- **Role split in progress.** `github-actions-ecr-push` exists for the build job. Once `kubernetes-deploy`'s build job assumes it, stage 2 removes `ref:refs/heads/main` and `AmazonEC2ContainerRegistryPowerUser` from `github-actions-deploy`, leaving it trusted only for `environment:production` with EKS access. Until then, the deploy role can still push to (or delete from) every ECR repository.
- The Lambda log group keeps 30 days of logs.
- `hello-world` has immutable tags, so a `latest` tag can't be moved after its first push.

## Drift detection

`.github/workflows/terraform-drift.yaml` runs daily at 12:00 UTC, and on demand from `main`. It uses the `drift` environment, which is limited to `main` and assumes the read-only `terraform-plan` role. It runs `terraform plan -detailed-exitcode` for `production` and `eks-dev`.

- **No changes:** the run passes.
- **Changes** (something changed outside Terraform, or a merged change hasn't been applied yet): the run fails, and a `drift` issue named `Drift detected: <stack>` is opened, or commented on if it's already open. Reconcile by applying the merged change, putting the manual change in code, or reverting it in AWS.
- **The next clean run for that stack closes its open issue automatically,** with a comment linking the run.
- The logs and the issue show only resource addresses and the plan summary. This repo's Actions logs are public, and full plans can contain values like the SSH CIDR.
- `account/` and `bootstrap/` aren't checked. They're applied by hand, and `bootstrap/` keeps its state locally.
- GitHub disables scheduled workflows in public repos after 60 days without activity. Re-enable it from the Actions tab if that happens.

The `drift` environment holds `AWS_ROLE_ARN` (`terraform-plan`) and `SSH_CIDR`.

## Account guardrails (`account/`)

Account-level controls, in a separate root module with state key `account/terraform.tfstate`:

- **CloudTrail:** trail `account-trail` (all regions, log file validation) and its log bucket `apotter-cloudtrail-549610932637`.
- **GitHub OIDC** (`github_oidc.tf`): CI gets short-lived credentials by assuming a role, not from a stored key.
  - `terraform-plan` has `ReadOnlyAccess` plus state-lock writes. It trusts the `production-plan`, `eks-dev`, and `drift` environments.
  - `terraform-apply` has `AdministratorAccess`, minus a self-protection deny. It can't touch these roles, the OIDC provider, the `Admins`/`Engineers` groups, human credentials, the trail, or the state and trail buckets. It trusts the `production` and `eks-dev-apply` environments, which only deploy from `main`.
  - The trust policies match GitHub's immutable subject format, `repo:aaronpotter@9371584/terraform-aws@1340975248:environment:<env>`. If a token is rejected, CloudTrail's denied `AssumeRoleWithWebIdentity` event shows the `sub` that was actually sent.
- **Human access** (`humans.tf`):
  - `Engineers` group: `ReadOnlyAccess`, `IAMUserChangePassword`, `SignInLocalDevelopmentAccess` (for `aws login`), state-lock writes so a local `terraform plan` works, and `sts:AssumeRole` on the break-glass role.
  - `break-glass-admin`: `AdministratorAccess` that only `apotter` can assume, with MFA used within the last hour. Sessions last at most 1 hour.
  - Alerts: in both `us-east-1` and `us-east-2`, EventBridge rules publish to an SNS topic `break-glass-alerts`, which emails `alert_email`. Each subscription must be confirmed once from its email.
    - `break-glass-assumed` matches `sts:AssumeRole` of `break-glass-admin`. A console role switch records that event in `us-east-1`, and the CLI records it in `us-east-2`, so each use sends one email.
    - `root-console-login` matches any root `ConsoleLogin`, whether it succeeds or fails. Sign-in events land in the region of the sign-in endpoint that was used, so a root sign-in through some other region's endpoint wouldn't alert.

**CI never applies this module**, and neither workflow plans or applies `account/**`. A human applies it after review, so a merged PR can't weaken the guardrails.

The alert email is set in the git-ignored `account/local.auto.tfvars`, which Terraform loads automatically, so the address stays out of this public repo:

```hcl
alert_email = "you@example.com"
```

### Local credentials

Humans use `aws login`, which gives short-lived credentials with no access keys. The pinned AWS provider can't read `aws login` credentials directly, so add these profiles to `~/.aws/config`:

```ini
# Read-only, for terraform plan. --profile default is required, or the inner aws call loops on AWS_PROFILE.
[profile terraform]
credential_process = aws configure export-credentials --profile default --format process
region = us-east-2

# Emergency admin. Prompts for an MFA code and triggers an alert email.
[profile break-glass]
role_arn         = arn:aws:iam::549610932637:role/break-glass-admin
source_profile   = terraform
mfa_serial       = arn:aws:iam::549610932637:mfa/apotter
duration_seconds = 3600
region           = us-east-2
```

Terraform can't prompt for an MFA code or read the CLI's cache of assumed-role credentials. To use break-glass, let the CLI assume the role (it prompts for the code) and export the session into the shell:

```sh
aws login
cd account
terraform init
AWS_PROFILE=terraform terraform plan -out=account.tfplan    # read-only is enough to plan

# applying needs admin: assume break-glass (MFA prompt, sends an alert), then apply the saved plan
( eval "$(aws configure export-credentials --profile break-glass --format env)"; terraform apply account.tfplan )
```

The subshell keeps the admin session out of your main shell, and it expires within an hour anyway.

### Switching a person to read-only (one time, in this order)

1. Apply `account/`, then click the confirmation link in both alert-subscription emails.
2. Test break-glass from the console (switch role to `break-glass-admin`) and from the CLI (`aws sts get-caller-identity --profile break-glass`). Confirm an alert email arrives for each.
3. Confirm `AWS_PROFILE=terraform terraform plan` works.
4. `aws iam add-user-to-group --group-name Engineers --user-name apotter`, **then** `aws iam remove-user-from-group --group-name Admins --user-name apotter`.

If anything goes wrong, the root user (MFA on) can fix IAM.
