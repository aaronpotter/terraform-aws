# Security+ practice exam (Node.js + PostgreSQL), deployed as its own Helm release into the
# production namespace.

# ------------------------------------------------------------------
# Image repository
# ------------------------------------------------------------------

resource "aws_ecr_repository" "security_plus_exam" {
  name                 = "security-plus-exam"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep the 20 newest tagged images. Untagged images are left alone: they are the platform/attestation
# manifests inside multi-arch indexes, and expiring them would break those tags.
resource "aws_ecr_lifecycle_policy" "security_plus_exam" {
  repository = aws_ecr_repository.security_plus_exam.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 20 newest tagged images"
      selection = {
        tagStatus      = "tagged"
        tagPatternList = ["*"]
        countType      = "imageCountMoreThan"
        countNumber    = 20
      }
      action = { type = "expire" }
    }]
  })
}

# ------------------------------------------------------------------
# CI roles (created only once var.secplus_github_subjects is set)
# ------------------------------------------------------------------
# Two roles: the build job may only push to this app's ECR repo, and only
# the production environment may deploy (see the EKS access entry in eks-dev/secplus.tf).

resource "aws_iam_role" "secplus_ecr_push" {
  count = length(var.secplus_github_subjects) > 0 ? 1 : 0

  name        = "github-actions-secplus-ecr-push"
  description = "Security+ exam build job: push images to the security-plus-exam ECR repository only."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Main branch only, e.g. "repo:aaronpotter@<owner id>/<repo>@<repo id>:ref:refs/heads/main"
          "token.actions.githubusercontent.com:sub" = [for s in var.secplus_github_subjects : "${s}:ref:refs/heads/main"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "secplus_ecr_push" {
  count = length(aws_iam_role.secplus_ecr_push)

  name = "push-security-plus-exam"
  role = aws_iam_role.secplus_ecr_push[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RegistryLogin"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushAndInspect"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeImages",
          "ecr:ListImages",
          "ecr:DescribeRepositories",
        ]
        Resource = aws_ecr_repository.security_plus_exam.arn
      },
    ]
  })
}

resource "aws_iam_role" "secplus_deploy" {
  count = length(var.secplus_github_subjects) > 0 ? 1 : 0

  name        = "github-actions-secplus-deploy"
  description = "Security+ exam deploy job: describe the cluster and run helm in the production namespace (edit access, via eks-dev)."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = [for s in var.secplus_github_subjects : "${s}:environment:production"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "secplus_deploy_eks_describe" {
  count = length(aws_iam_role.secplus_deploy)

  name = "eks-describe"
  role = aws_iam_role.secplus_deploy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = "*"
    }]
  })
}

# ------------------------------------------------------------------
# CloudFront (created only once the app's load balancer exists)
# ------------------------------------------------------------------
# The Service's load balancer is created by Kubernetes on first deploy, so its hostname is an input
# (var.secplus_origin_domain). Leave it empty for the first apply; set it after the first helm
# install to create the distribution.

resource "random_password" "secplus_origin_verify" {
  length  = 48
  special = false
}

# Raw header value (not JSON), read at runtime by the app pods. Name chosen so it does NOT match the
# old "apotterlab-origin-verify-??????" pattern still present in account/github_oidc.tf.
resource "aws_secretsmanager_secret" "secplus_origin_verify" {
  name        = "apotterlab-secplus-origin-verify"
  description = "Raw X-Origin-Verify header value CloudFront sends to the Security+ exam load balancer (not JSON)."
}

resource "aws_secretsmanager_secret_version" "secplus_origin_verify" {
  secret_id     = aws_secretsmanager_secret.secplus_origin_verify.id
  secret_string = random_password.secplus_origin_verify.result
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# ------------------------------------------------------------------
# Custom domain: imported wildcard certificate, and a Host check so ONLY that domain works
# ------------------------------------------------------------------
# DNS for turbocerts.com lives in Cloudflare (not managed here). The certificate below was created
# and validated by hand; it is imported so Terraform tracks it and keeps the distribution's alias
# and certificate from drifting.

import {
  provider = aws.us_east_1
  to       = aws_acm_certificate.turbocerts
  id       = "arn:aws:acm:us-east-1:549610932637:certificate/18f660ae-302f-403e-8c93-722e628c0915"
}

# CloudFront only accepts certificates from us-east-1. A wildcard, so other turbocerts.com
# subdomains can reuse it: don't destroy it casually.
resource "aws_acm_certificate" "turbocerts" {
  provider = aws.us_east_1

  domain_name       = "*.turbocerts.com"
  validation_method = "DNS"

  lifecycle {
    prevent_destroy = true
  }
}

# Viewer-request check: anything not addressed to the custom domain (notably the default
# *.cloudfront.net name) gets 403 before it reaches the origin.
resource "aws_cloudfront_function" "secplus_host_check" {
  count = var.secplus_domain != "" ? 1 : 0

  name    = "secplus-host-check"
  runtime = "cloudfront-js-2.0"
  comment = "Only serve ${var.secplus_domain}"
  publish = true

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var host = request.headers.host ? request.headers.host.value.toLowerCase() : "";
      if (host !== "${lower(var.secplus_domain)}") {
        return { statusCode: 403, statusDescription: "Forbidden" };
      }
      return request;
    }
  EOT
}

resource "aws_cloudfront_distribution" "secplus" {
  count = var.secplus_origin_domain != "" ? 1 : 0

  comment         = "Security+ practice exam via the EKS Service load balancer"
  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"
  aliases         = var.secplus_domain != "" ? [var.secplus_domain] : []

  origin {
    origin_id   = "secplus-lb"
    domain_name = var.secplus_origin_domain

    # The in-tree Service LB listens on HTTP only, so the CloudFront-to-origin hop (and this header)
    # is unencrypted. Viewers always get HTTPS.
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.secplus_origin_verify.result
    }
  }

  default_cache_behavior {
    target_origin_id       = "secplus-lb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # Exam attempts are per-user API responses and must never be cached.
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    dynamic "function_association" {
      for_each = var.secplus_domain != "" ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.secplus_host_check[0].arn
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.secplus_domain != "" ? null : true
    acm_certificate_arn            = var.secplus_domain != "" ? aws_acm_certificate.turbocerts.arn : null
    ssl_support_method             = var.secplus_domain != "" ? "sni-only" : null
    minimum_protocol_version       = var.secplus_domain != "" ? "TLSv1.2_2021" : null
  }
}

# ------------------------------------------------------------------
# Apex domain (turbocerts.com): second distribution, same origin
# ------------------------------------------------------------------
# Created by hand in the console ("For TurboCerts home site"), then imported here and brought in line
# with the subdomain distribution: HTTP to the origin, X-Origin-Verify header, no caching, Host check.
# CloudFront takes one certificate per distribution, so the apex has its own (the wildcard above does
# not cover it). Both are created and validated by hand and imported.

import {
  provider = aws.us_east_1
  to       = aws_acm_certificate.turbocerts_apex
  id       = "arn:aws:acm:us-east-1:549610932637:certificate/73f4c4bb-982b-4178-a32b-3489f90b3a56"
}

resource "aws_acm_certificate" "turbocerts_apex" {
  provider = aws.us_east_1

  domain_name       = "turbocerts.com"
  validation_method = "DNS"

  lifecycle {
    prevent_destroy = true
  }
}

import {
  to = aws_cloudfront_distribution.secplus_apex
  id = "E19LJGLXCXBSC9"
}

resource "aws_cloudfront_function" "secplus_apex_host_check" {
  name    = "secplus-apex-host-check"
  runtime = "cloudfront-js-2.0"
  comment = "Only serve ${var.secplus_apex_domain}"
  publish = true

  code = <<-EOT
    function handler(event) {
      var request = event.request;
      var host = request.headers.host ? request.headers.host.value.toLowerCase() : "";
      if (host !== "${lower(var.secplus_apex_domain)}") {
        return { statusCode: 403, statusDescription: "Forbidden" };
      }
      return request;
    }
  EOT
}

resource "aws_cloudfront_distribution" "secplus_apex" {
  comment         = "For TurboCerts home site"
  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"
  aliases         = [var.secplus_apex_domain]

  origin {
    origin_id   = "secplus-lb"
    domain_name = var.secplus_origin_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = random_password.secplus_origin_verify.result
    }
  }

  default_cache_behavior {
    target_origin_id       = "secplus-lb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.secplus_apex_host_check.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.turbocerts_apex.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
