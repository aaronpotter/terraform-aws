provider "aws" {
  region = var.region

  # Marks every resource as Terraform-managed, and says where its code lives.
  default_tags {
    tags = {
      ManagedBy = "terraform"
      Repo      = "aaronpotter/terraform-aws"
      Stack     = "bootstrap"
    }
  }
}

data "aws_caller_identity" "current" {}

locals {
  iam = "arn:aws:iam::${data.aws_caller_identity.current.account_id}"

  # Root is always exempt: it can recover from a bad bucket policy regardless.
  root = "${local.iam}:root"

  # Who may write state (*.tfstate). CI applies as terraform-apply; humans only via break-glass.
  state_writers = concat(["${local.iam}:role/terraform-apply", "${local.iam}:role/break-glass-admin", local.root], var.extra_state_writer_arns)

  # Who may take and release the state lock (*.tflock): the writers, plus anyone who runs plan.
  lock_writers = concat(local.state_writers, ["${local.iam}:role/terraform-plan"], var.lock_writer_arns)

  # Who may change the guardrails on this bucket or destroy history.
  bucket_admins = ["${local.iam}:role/break-glass-admin", local.root]
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.state_bucket_name

  lifecycle {
    # Deleting this bucket would take every state file with it.
    prevent_destroy = true
  }

  tags = {
    Name = var.state_bucket_name
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    # The recovery path if a state write goes bad.
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # Applied after the public access block so the policy isn't evaluated as public.
  depends_on = [aws_s3_bucket_public_access_block.tfstate]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*",
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      },
      {
        # Even account admins can't overwrite or delete state without break-glass.
        Sid       = "DenyStateWritesExceptAppliers"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:PutObject", "s3:DeleteObject"]
        Resource  = "${aws_s3_bucket.tfstate.arn}/*.tfstate"
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = local.state_writers }
        }
      },
      {
        Sid       = "DenyLockWritesExceptPlanners"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:PutObject", "s3:DeleteObject"]
        Resource  = "${aws_s3_bucket.tfstate.arn}/*.tflock"
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = local.lock_writers }
        }
      },
      {
        # Old versions are the recovery path for a bad state write; lifecycle expiry still applies.
        Sid       = "DenyVersionDeletion"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:DeleteObjectVersion"]
        Resource  = "${aws_s3_bucket.tfstate.arn}/*"
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = local.bucket_admins }
        }
      },
      {
        Sid       = "DenyGuardrailChanges"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:PutBucketVersioning",
          "s3:PutLifecycleConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:PutBucketPublicAccessBlock",
        ]
        Resource = aws_s3_bucket.tfstate.arn
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = local.bucket_admins }
        }
      },
    ]
  })
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # Versioning must be on before noncurrent-version rules mean anything.
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    # Keep a recent window of prior state for recovery without growing forever.
    noncurrent_version_expiration {
      noncurrent_days           = 90
      newer_noncurrent_versions = 10
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
