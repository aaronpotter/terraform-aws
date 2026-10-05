# TurboCerts landing page (turbocerts.com): static files in a private S3 bucket, served by the apex
# CloudFront distribution through Origin Access Control. Uploaded by the aaronpotter/turbocerts-home
# repo's workflow.
#
# The apex distribution (aws_cloudfront_distribution.secplus_apex in secplus.tf) serves this bucket.

resource "aws_s3_bucket" "turbocerts_home" {
  bucket = "apotter-turbocerts-home"
}

resource "aws_s3_bucket_public_access_block" "turbocerts_home" {
  bucket                  = aws_s3_bucket.turbocerts_home.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "turbocerts_home" {
  bucket = aws_s3_bucket.turbocerts_home.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "turbocerts_home" {
  bucket = aws_s3_bucket.turbocerts_home.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# The deploy runs `aws s3 sync --delete`; versioning lets a bad deploy be undone.
resource "aws_s3_bucket_versioning" "turbocerts_home" {
  bucket = aws_s3_bucket.turbocerts_home.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "turbocerts_home" {
  bucket = aws_s3_bucket.turbocerts_home.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.turbocerts_home]
}

resource "aws_cloudfront_origin_access_control" "turbocerts_home" {
  name                              = "turbocerts-home"
  description                       = "CloudFront access to the turbocerts-home bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Only the apex distribution may read objects.
resource "aws_s3_bucket_policy" "turbocerts_home" {
  bucket = aws_s3_bucket.turbocerts_home.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowApexDistributionRead"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.turbocerts_home.arn}/*"
      Condition = {
        StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.secplus_apex.arn }
      }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.turbocerts_home]
}

# ------------------------------------------------------------------
# CI role (created only once var.turbocerts_home_github_subjects is set)
# ------------------------------------------------------------------
# Main branch only; may write to this bucket and invalidate the apex distribution, nothing else.

resource "aws_iam_role" "turbocerts_home_deploy" {
  count = length(var.turbocerts_home_github_subjects) > 0 ? 1 : 0

  name        = "github-actions-turbocerts-home-deploy"
  description = "turbocerts-home deploy job: sync the site to its S3 bucket and invalidate the apex CloudFront distribution."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = [for s in var.turbocerts_home_github_subjects : "${s}:ref:refs/heads/main"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "turbocerts_home_deploy" {
  count = length(aws_iam_role.turbocerts_home_deploy)

  name = "sync-site-and-invalidate"
  role = aws_iam_role.turbocerts_home_deploy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.turbocerts_home.arn
      },
      {
        Sid      = "WriteObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"]
        Resource = "${aws_s3_bucket.turbocerts_home.arn}/*"
      },
      {
        Sid      = "Invalidate"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = aws_cloudfront_distribution.secplus_apex.arn
      },
    ]
  })
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}
