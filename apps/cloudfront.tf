# CloudFront in front of the kubernetes-deploy app's load balancer. The app rejects any request
# without a matching X-Origin-Verify header, so the app is reachable only through this distribution.
#
# The load balancer is created by Kubernetes (Service type LoadBalancer), not Terraform, so its
# hostname is an input: after the cluster is recreated, update origin_domain in terraform.tfvars or
# CloudFront returns 502/504. This stack is always on, so the cloudfront.net URL survives the
# eks-dev enabled switch.

# The header value must appear in both the secret (for the app) and CloudFront's config, so it's in
# Terraform state by necessity. It's sensitive, so plans in the public CI logs show "(sensitive value)".
resource "random_password" "origin_verify" {
  length  = 48
  special = false
}

resource "aws_secretsmanager_secret" "origin_verify" {
  name        = "apotterlab-origin-verify"
  description = "Raw X-Origin-Verify header value CloudFront sends to the app's load balancer (not JSON)."
}

# Refreshing this calls GetSecretValue, so terraform-plan has read access to this one secret
# (account/github_oidc.tf). That adds no exposure: the value is already in state, which it can read.
resource "aws_secretsmanager_secret_version" "origin_verify" {
  secret_id     = aws_secretsmanager_secret.origin_verify.id
  secret_string = random_password.origin_verify.result
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "app" {
  comment         = "kubernetes-deploy app (hello-world) via the EKS Service load balancer"
  enabled         = true
  is_ipv6_enabled = true
  price_class     = "PriceClass_100"

  origin {
    origin_id   = "app-lb"
    domain_name = var.origin_domain

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
      value = random_password.origin_verify.result
    }
  }

  default_cache_behavior {
    target_origin_id       = "app-lb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # API responses (task lists) must never be served stale; forward all viewer headers except Host.
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
