# One-time adoption of resources created by hand before this module existed. The CI apply performs
# the import as terraform-apply; after that these blocks are no-ops and can be deleted.

import {
  for_each = local.unzip_buckets
  to       = aws_s3_bucket.unzip[each.key]
  id       = each.value.name
}

import {
  for_each = local.unzip_buckets
  to       = aws_s3_bucket_server_side_encryption_configuration.unzip[each.key]
  id       = each.value.name
}

import {
  for_each = local.unzip_buckets
  to       = aws_s3_bucket_public_access_block.unzip[each.key]
  id       = each.value.name
}

import {
  for_each = local.unzip_buckets
  to       = aws_s3_bucket_ownership_controls.unzip[each.key]
  id       = each.value.name
}

import {
  to = aws_iam_role.unzip
  id = "lambda-s3-trigger-role"
}

import {
  to = aws_iam_policy.unzip
  id = "arn:aws:iam::549610932637:policy/s3-trigger"
}

import {
  to = aws_iam_role_policy_attachment.unzip
  id = "lambda-s3-trigger-role/arn:aws:iam::549610932637:policy/s3-trigger"
}

import {
  to = aws_cloudwatch_log_group.unzip
  id = "/aws/lambda/s3-trigger-unzip"
}

import {
  to = aws_lambda_function.unzip
  id = "s3-trigger-unzip"
}

import {
  to = aws_lambda_permission.unzip_from_input
  id = "s3-trigger-unzip/lambda-398fe368-16d2-487f-b594-773995fe92d1"
}

import {
  to = aws_s3_bucket_notification.unzip_input
  id = "apotter-lambda-input"
}

import {
  to = aws_ecr_repository.hello_world
  id = "hello-world"
}

import {
  to = aws_iam_role.github_deploy
  id = "github-actions-deploy"
}

import {
  to = aws_iam_role_policy_attachment.github_deploy_ecr
  id = "github-actions-deploy/arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

import {
  to = aws_iam_role_policy.github_deploy_eks_describe
  id = "github-actions-deploy:eks-describe"
}
