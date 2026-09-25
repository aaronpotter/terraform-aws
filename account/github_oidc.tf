# GitHub Actions authenticates to AWS with short-lived OIDC tokens instead of a stored access key.
# terraform-plan: read-only, for PR/dispatch plans. terraform-apply: admin, only from main-only environments.

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

locals {
  # The repo uses GitHub's immutable subject format (owner and repo IDs), so renames can't
  # redirect trust. Check with: gh api repos/aaronpotter/terraform-aws/actions/oidc/customization/sub
  github_sub_prefix = "repo:${var.github_owner}@${var.github_owner_id}/${var.github_repo}@${var.github_repo_id}:environment"

  # The environment claim carries no branch; each environment's deployment-branch policy is what
  # keeps the apply environments on main.
  plan_environments  = ["production-plan", "eks-dev", "drift"]
  apply_environments = ["production", "eks-dev-apply"]

  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
}

data "aws_iam_policy_document" "github_trust" {
  for_each = {
    plan  = local.plan_environments
    apply = local.apply_environments
  }

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [for env in each.value : "${local.github_sub_prefix}:${env}"]
    }
  }
}

# ------------------------------------------------------------------
# terraform-plan
# ------------------------------------------------------------------

resource "aws_iam_role" "terraform_plan" {
  name                 = "terraform-plan"
  description          = "GitHub Actions plans (PRs and manual runs). Read-only plus state locking."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["plan"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "terraform_plan_readonly" {
  role       = aws_iam_role.terraform_plan.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

data "aws_iam_policy_document" "terraform_plan_state_lock" {
  statement {
    sid       = "StateLockFiles"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*.tflock"]
  }
}

resource "aws_iam_role_policy" "terraform_plan_state_lock" {
  name   = "state-lock"
  role   = aws_iam_role.terraform_plan.id
  policy = data.aws_iam_policy_document.terraform_plan_state_lock.json
}

# ------------------------------------------------------------------
# terraform-apply
# ------------------------------------------------------------------

resource "aws_iam_role" "terraform_apply" {
  name                 = "terraform-apply"
  description          = "GitHub Actions applies from main. Admin, minus the guardrails in the self-protection policy."
  assume_role_policy   = data.aws_iam_policy_document.github_trust["apply"].json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "terraform_apply_admin" {
  role       = aws_iam_role.terraform_apply.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Whoever can merge to main controls this role, so it must not be able to weaken the controls
# around it. It can still create other IAM roles (eks-dev needs that); PR review covers that risk.
data "aws_iam_policy_document" "terraform_apply_self_protection" {
  statement {
    sid     = "DenyGuardrailIdentities"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/terraform-plan",
      "arn:aws:iam::${local.account_id}:role/terraform-apply",
      "arn:aws:iam::${local.account_id}:role/break-glass-admin",
      "arn:aws:iam::${local.account_id}:group/Admins",
      "arn:aws:iam::${local.account_id}:group/Engineers",
      aws_iam_openid_connect_provider.github.arn,
    ]
  }

  statement {
    sid    = "DenyHumanCredentialChanges"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
      "iam:AddUserToGroup",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyTrailTampering"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors",
      "cloudtrail:PutInsightSelectors",
    ]
    resources = [local.trail_arn]
  }

  statement {
    sid    = "DenyGuardrailBucketChanges"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutLifecycleConfiguration",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
    ]
    resources = [local.state_bucket_arn, aws_s3_bucket.trail.arn]
  }

  statement {
    sid       = "DenyTrailLogDeletion"
    effect    = "Deny"
    actions   = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
    resources = ["${aws_s3_bucket.trail.arn}/*"]
  }
}

resource "aws_iam_role_policy" "terraform_apply_self_protection" {
  name   = "self-protection"
  role   = aws_iam_role.terraform_apply.id
  policy = data.aws_iam_policy_document.terraform_apply_self_protection.json
}
