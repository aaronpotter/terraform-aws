# One region's alerting: an EventBridge rule on CloudTrail events for the break-glass role,
# publishing to an SNS topic with an email subscription. CloudTrail events reach EventBridge only
# in the region they're recorded in, so this is instantiated per region.

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
  role_name      = element(split("/", var.role_arn), length(split("/", var.role_arn)) - 1)
  account_id     = element(split(":", var.role_arn), 4)
  session_prefix = "arn:aws:sts::${local.account_id}:assumed-role/${local.role_name}/"
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
  description = "Break-glass role ${local.role_name} was assumed (CLI AssumeRole or console SwitchRole)."

  event_pattern = jsonencode({
    source      = ["aws.sts", "aws.signin"]
    detail-type = ["AWS API Call via CloudTrail", "AWS Console Sign In via CloudTrail"]
    "$or" = [
      { detail = { eventName = ["AssumeRole"], requestParameters = { roleArn = [var.role_arn] } } },
      { detail = { eventName = ["SwitchRole"], userIdentity = { arn = [{ prefix = local.session_prefix }] } } },
    ]
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

data "aws_iam_policy_document" "topic" {
  statement {
    sid       = "AllowThisRuleToPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alert.arn]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.assumed.arn]
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
