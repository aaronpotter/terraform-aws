# One region's alerting: EventBridge rules on CloudTrail events for the break-glass role and for
# root console sign-ins, publishing to an SNS topic with an email subscription. CloudTrail events
# reach EventBridge only in the region they're recorded in, so this is instantiated per region.

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "role_arn" {
  description = "ARN of the break-glass role to watch."
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the alert topic."
  type        = string
}

data "aws_region" "current" {}

locals {
  role_name = element(split("/", var.role_arn), length(split("/", var.role_arn)) - 1)
}

resource "aws_sns_topic" "alert" {
  name = "break-glass-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alert.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_event_rule" "assumed" {
  name        = "break-glass-assumed"
  description = "Break-glass role ${local.role_name} was assumed (CLI or console)."

  # A console role switch also records sts:AssumeRole (verified 2026-09-25), so matching
  # AssumeRole alone covers both paths; matching SwitchRole too sent two emails per switch.
  event_pattern = jsonencode({
    source      = ["aws.sts"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventName         = ["AssumeRole"]
      requestParameters = { roleArn = [var.role_arn] }
    }
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  rule = aws_cloudwatch_event_rule.assumed.name
  arn  = aws_sns_topic.alert.arn

  input_transformer {
    input_paths = {
      event  = "$.detail.eventName"
      caller = "$.detail.userIdentity.arn"
      time   = "$.detail.eventTime"
      ip     = "$.detail.sourceIPAddress"
      region = "$.region"
    }
    input_template = "\"Break-glass ${local.role_name}: <event> by <caller> at <time> from <ip> (<region>). Put any change made with it into code today.\""
  }
}

# Root bypasses every IAM guardrail, so any console sign-in attempt (success or failure) alerts.
# Sign-in events are recorded in the region of the sign-in endpoint used, which is why this rule
# lives in each regional copy of the module.
resource "aws_cloudwatch_event_rule" "root_login" {
  name        = "root-console-login"
  description = "Root user console sign-in attempt."

  event_pattern = jsonencode({
    source      = ["aws.signin"]
    detail-type = ["AWS Console Sign In via CloudTrail"]
    detail = {
      eventName    = ["ConsoleLogin"]
      userIdentity = { type = ["Root"] }
    }
  })
}

resource "aws_cloudwatch_event_target" "root_login_sns" {
  rule = aws_cloudwatch_event_rule.root_login.name
  arn  = aws_sns_topic.alert.arn

  input_transformer {
    input_paths = {
      result = "$.detail.responseElements.ConsoleLogin"
      mfa    = "$.detail.additionalEventData.MFAUsed"
      time   = "$.detail.eventTime"
      ip     = "$.detail.sourceIPAddress"
      region = "$.region"
    }
    input_template = "\"Root console sign-in: <result> at <time> from <ip> (<region>), MFA used: <mfa>. If this wasn't you, rotate the root password and MFA now.\""
  }
}

data "aws_iam_policy_document" "topic" {
  statement {
    sid       = "AllowThisModulesRulesToPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alert.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.assumed.arn, aws_cloudwatch_event_rule.root_login.arn]
    }
  }
}

resource "aws_sns_topic_policy" "alert" {
  arn    = aws_sns_topic.alert.arn
  policy = data.aws_iam_policy_document.topic.json
}

output "topic_arn" {
  value = aws_sns_topic.alert.arn
}

output "region" {
  value = data.aws_region.current.name
}
