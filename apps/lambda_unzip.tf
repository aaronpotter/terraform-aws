# s3-trigger-unzip: a .gz object landing in apotter-lambda-input is decompressed into
# apotter-lambda-output, then deleted from the input bucket.

locals {
  unzip_function_name = "s3-trigger-unzip"

  unzip_buckets = {
    input   = { name = "apotter-lambda-input", bucket_key = true }
    output  = { name = "apotter-lambda-output", bucket_key = true }
    scripts = { name = "apotter-lambda-scripts", bucket_key = false }
  }
}

# ------------------------------------------------------------------
# Buckets
# ------------------------------------------------------------------

resource "aws_s3_bucket" "unzip" {
  for_each = local.unzip_buckets

  bucket = each.value.name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "unzip" {
  for_each = local.unzip_buckets

  bucket = aws_s3_bucket.unzip[each.key].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = each.value.bucket_key
  }
}

resource "aws_s3_bucket_public_access_block" "unzip" {
  for_each = local.unzip_buckets

  bucket = aws_s3_bucket.unzip[each.key].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "unzip" {
  for_each = local.unzip_buckets

  bucket = aws_s3_bucket.unzip[each.key].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ------------------------------------------------------------------
# IAM
# ------------------------------------------------------------------

resource "aws_iam_role" "unzip" {
  name        = "lambda-s3-trigger-role"
  description = "Allows Lambda functions to call AWS services on your behalf."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "unzip" {
  name = "s3-trigger"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents", "logs:CreateLogGroup", "logs:CreateLogStream"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Sid      = "AllowReadFromSourceBucket"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.unzip["input"].arn}/*"
      },
      {
        Sid      = "AllowWriteToDestinationBucket"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.unzip["output"].arn}/*"
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "unzip" {
  role       = aws_iam_role.unzip.name
  policy_arn = aws_iam_policy.unzip.arn
}

# ------------------------------------------------------------------
# Function
# ------------------------------------------------------------------

# Built on each plan from the source in this repo. CI uploads build/ with the saved plan so the
# apply job has the same zip.
data "archive_file" "unzip" {
  type        = "zip"
  source_file = "${path.module}/lambda/s3-trigger-unzip/lambda_function.py"
  output_path = "${path.module}/build/s3-trigger-unzip.zip"
}

resource "aws_cloudwatch_log_group" "unzip" {
  name = "/aws/lambda/${local.unzip_function_name}"
}

resource "aws_lambda_function" "unzip" {
  function_name    = local.unzip_function_name
  role             = aws_iam_role.unzip.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.14"
  architectures    = ["x86_64"]
  memory_size      = 128
  timeout          = 3
  filename         = data.archive_file.unzip.output_path
  source_code_hash = data.archive_file.unzip.output_base64sha256

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.unzip.name
  }
}

resource "aws_lambda_permission" "unzip_from_input" {
  statement_id   = "lambda-398fe368-16d2-487f-b594-773995fe92d1"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.unzip.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.unzip["input"].arn
  source_account = local.account_id
}

resource "aws_s3_bucket_notification" "unzip_input" {
  bucket = aws_s3_bucket.unzip["input"].id

  lambda_function {
    id                  = "a59a63c7-b9c3-419d-8e90-0c7815c8e1b2"
    lambda_function_arn = aws_lambda_function.unzip.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".gz"
  }

  depends_on = [aws_lambda_permission.unzip_from_input]
}
