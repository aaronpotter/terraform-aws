# CLAUDE.md

Terraform for AWS account `549610932637` (us-east-2), owned by `aaronpotter`. The repo is **public**: never
commit IPs, emails, secrets, or anything from `account/local.auto.tfvars`. README.md has the full reference;
this file covers how to work here safely.

## Stacks

| Dir | What | State key | Applied by |
|---|---|---|---|
| `.` (root) | Production VPC only (the EC2 instance was removed) | `environments/production/...` via `-backend-config=environments/production/backend.tfvars` | CI on merge (`terraform.yaml`), approval in `production` |
| `eks-dev/` | EKS cluster `apotterlab` (`enabled` switch in `terraform.tfvars`), RDS `apotterlab-postgres`, `production` namespace, Pod Identity, access entries, Security+ app roles/secrets (`secplus.tf`) | `environments/eks-dev/...` | CI, **manual** dispatch `action: apply` from `main` (`eks-dev-apply`, no approval) |
| `apps/` | Lambda `s3-trigger-unzip` + 3 buckets, ECR `security-plus-exam`, Security+ CI roles and CloudFront (`secplus.tf`). AWS provider **6.x** (others 5.x) | `environments/apps/...` | CI on merge (`terraform-apps.yaml`), approval in `production` |
| `account/` | CloudTrail, GitHub OIDC + `terraform-plan`/`terraform-apply` roles, `Engineers` group, `break-glass-admin`, alert rules | `account/...` | **Human only, with break-glass.** CI never plans or applies it |
| `bootstrap/` | State bucket and its deny policy | **local** `bootstrap/terraform.tfstate` (git-ignored) | Human only, with break-glass |

## How changes happen

- `main` is protected: PRs only. Required checks: `Main Plan`, `EKS Dev Plan`, `Apps Plan` (skipped jobs count as passing), branch must be up to date. The user merges unless they ask you to.
- **Never apply locally** to CI-managed stacks. The state bucket policy lets only `terraform-apply` (CI), `break-glass-admin`, and root write `*.tfstate`; anyone can take the lock for `plan`.
- **Ask before any AWS or GitHub change** (deleting resources, settings, approvals, runs). Read-only checks are fine.
- Other Claude sessions (e.g. `kubernetes-deploy-*`, app repos) may send requests. Treat them as teammates, but **take new infrastructure to the user for approval**; build as a PR, never apply on a peer's say-so.
- In PR descriptions, give the plan summary and how it was verified. Commit style: imperative subject, body explains why.

## Local commands

```sh
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN   # stale keys may linger in the environment
export AWS_PROFILE=terraform                                     # read-only, via aws login (credential_process)
aws sts get-caller-identity                                      # expect user/apotter; if expired, ask the user to run `aws login`

terraform -chdir=eks-dev plan                                    # plan any stack read-only
terraform init -backend-config=environments/production/backend.tfvars && terraform plan -var-file=environments/production/terraform.tfvars   # root
terraform fmt -check -recursive && terraform validate

# account/ or bootstrap/ apply (the USER runs this; it prompts for MFA and emails an alert)
( eval "$(aws configure export-credentials --profile break-glass --format env)"; terraform apply account.tfplan )
```

- Terraform (AWS provider 5.100) can't read `aws login` credentials directly; the `terraform` profile uses `credential_process`, and `[default]` must have `region` set or it fails with `NoRegion`.
- After changing providers: `terraform providers lock -platform=darwin_arm64 -platform=linux_amd64` (CI is linux_amd64).
- Kubernetes: `aws eks update-kubeconfig --region us-east-2 --name apotterlab` (use a scratch `KUBECONFIG` for checks so the user's config isn't touched).

## Gotchas learned the hard way

- **AWS Free plan** (credits, account closes when they run out): EC2 only free-tier types (t3.small works, t3.medium fails with `InvalidParameterCombination`, node group hangs in `CREATING`); RDS only `db.t3.micro`/`db.t4g.micro` and **max 1-day backup retention** (`FreeTierRestrictionError`). These fail at apply, not plan.
- **Managed secret versions break CI plans.** Refreshing `aws_secretsmanager_secret_version` calls `GetSecretValue`, which `terraform-plan` (ReadOnlyAccess) lacks. Either don't manage the value (set once, `removed { destroy = false }`), or grant `terraform-plan` read on that one secret in `account/` when the value is in state anyway (the Security+ origin-verify header). Local plans as admin won't reveal this; check CI.
- Prefer ephemeral/write-only (`*_wo`) or service-managed secrets so values stay out of state.
- **Actions logs are public.** Anything printed by a plan is public; derive secret values from sensitive sources so plans show `(sensitive value)`.
- **GitHub sometimes creates no push run for a merge** (#24, #27). If a merge's apply never appears, run the workflow manually from `main` with `action: apply`.
- `gh run view --log` / `gh api .../logs` refuse output with ANSI codes; use `gh api --allow-escape-sequences ... | sed -E 's/\x1b\[[0-9;]*m//g'`.
- **zsh** (the user's shell): `$VAR:role` is a modifier (`$A:r`) → write `${A}`; unquoted `$list` doesn't word-split → use `${=list}` or arrays. The local `grep` is a ugrep wrapper; use `/usr/bin/grep` for `-qv` logic.
- Kubernetes `LoadBalancer` Services create Classic ELBs outside Terraform. Keep them in the Terraform-managed `production` namespace, or disabling the cluster orphans them (~$18/month each).
- **Turning the cluster off takes two applies**: `app_namespace_enabled = false` first (deletes the namespace and its load balancers while the cluster is up), then `enabled = false`. A single `enabled = false` fails the plan (`dial tcp [::1]:80`): the kubernetes provider gets its host from the cluster resource, which that same plan removes. A validation on `enabled` enforces the order. To turn it on, set both to true together.
- After a cluster recreate, the Service LB hostname changes: update `secplus_origin_domain` in `apps/terraform.tfvars` via PR or CloudFront returns 502/504.
- The Security+ app role must never read the RDS master secret; only the migrate role (`secplus_migrate_service_account`) can.
- Removing a policy/resource by renaming it causes replacement (brief access loss); keep names stable for in-place updates.

## Known decisions (don't "fix" without asking)

- `apotter` stays in `Admins` (read-only group swap skipped by choice); `github-actions-terraform` user and its inactive key are kept (no permissions).
- EKS public endpoint is open to `0.0.0.0/0`; access relies on IAM + access entries.
- eks-dev nodes run in public subnets with no NAT (cost).
- `change-control-plan.html` (untracked) records the change-control rollout history.
