# Human access: read-only day to day, admin only through an MFA-gated, alerting break-glass role.
# Group membership is changed by hand after the break-glass path is tested (see README).

locals {
  break_glass_role_name = "break-glass-admin"
}

# ------------------------------------------------------------------
# break-glass-admin
# ------------------------------------------------------------------

data "aws_iam_policy_document" "break_glass_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = var.break_glass_user_arns
    }

    condition {
      test     = "Bool"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["true"]
    }

    # MFA within the last hour, so a long-lived console session can't reach admin on stale MFA.
    condition {
      test     = "NumericLessThan"
      variable = "aws:MultiFactorAuthAge"
      values   = ["3600"]
    }
  }
}

resource "aws_iam_role" "break_glass" {
  name                 = local.break_glass_role_name
  description          = "Emergency admin. MFA required, 1-hour sessions, every assumption emails an alert."
  assume_role_policy   = data.aws_iam_policy_document.break_glass_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "break_glass_admin" {
  role       = aws_iam_role.break_glass.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# Console role switches are recorded in us-east-1 (global sign-in events); CLI AssumeRole calls in
# the region of the STS endpoint used, us-east-2 here.
module "break_glass_alert_us_east_1" {
  source      = "./modules/break-glass-alert"
  providers   = { aws = aws.us_east_1 }
  role_arn    = aws_iam_role.break_glass.arn
  alert_email = var.alert_email
}

module "break_glass_alert_home" {
  source      = "./modules/break-glass-alert"
  role_arn    = aws_iam_role.break_glass.arn
  alert_email = var.alert_email
}

# ------------------------------------------------------------------
# Engineers: read-only, can run terraform plan and assume break-glass
# ------------------------------------------------------------------

resource "aws_iam_group" "engineers" {
  name = "Engineers"
}

resource "aws_iam_group_policy_attachment" "engineers" {
  for_each = toset([
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    "arn:aws:iam::aws:policy/IAMUserChangePassword",
    # Lets `aws login` exchange a console session for CLI credentials.
    "arn:aws:iam::aws:policy/SignInLocalDevelopmentAccess",
  ])

  group      = aws_iam_group.engineers.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "engineers" {
  statement {
    sid       = "StateLockFilesForLocalPlan"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${local.state_bucket_arn}/*.tflock"]
  }

  statement {
    sid       = "AssumeBreakGlass"
    actions   = ["sts:AssumeRole"]
    resources = [aws_iam_role.break_glass.arn]
  }
}

resource "aws_iam_group_policy" "engineers" {
  name   = "plan-and-break-glass"
  group  = aws_iam_group.engineers.name
  policy = data.aws_iam_policy_document.engineers.json
}
