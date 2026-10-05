# AWS DevOps practice exam (Node.js + PostgreSQL), deployed as its own Helm release into the
# production namespace. Same model as secplus.tf; no CloudFront yet (see README).

# ------------------------------------------------------------------
# Image repository
# ------------------------------------------------------------------

resource "aws_ecr_repository" "aws_devops_exam" {
  name                 = "aws-devops-exam"
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
resource "aws_ecr_lifecycle_policy" "aws_devops_exam" {
  repository = aws_ecr_repository.aws_devops_exam.name

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
# CI roles (created only once var.awsdevops_github_subjects is set)
# ------------------------------------------------------------------
# Two roles: the build job may only push to this app's ECR repo, and only the production
# environment may deploy (see the EKS access entry in eks-dev/awsdevops.tf).

resource "aws_iam_role" "awsdevops_ecr_push" {
  count = length(var.awsdevops_github_subjects) > 0 ? 1 : 0

  name        = "github-actions-awsdevops-ecr-push"
  description = "AWS DevOps exam build job: push images to the aws-devops-exam ECR repository only."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          # Main branch only, pinned by immutable IDs.
          "token.actions.githubusercontent.com:sub" = [for s in var.awsdevops_github_subjects : "${s}:ref:refs/heads/main"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "awsdevops_ecr_push" {
  count = length(aws_iam_role.awsdevops_ecr_push)

  name = "push-aws-devops-exam"
  role = aws_iam_role.awsdevops_ecr_push[0].id

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
        Resource = aws_ecr_repository.aws_devops_exam.arn
      },
    ]
  })
}

resource "aws_iam_role" "awsdevops_deploy" {
  count = length(var.awsdevops_github_subjects) > 0 ? 1 : 0

  name        = "github-actions-awsdevops-deploy"
  description = "AWS DevOps exam deploy job: describe the cluster and run helm in the production namespace (edit access, via eks-dev)."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = [for s in var.awsdevops_github_subjects : "${s}:environment:production"]
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "awsdevops_deploy_eks_describe" {
  count = length(aws_iam_role.awsdevops_deploy)

  name = "eks-describe"
  role = aws_iam_role.awsdevops_deploy[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = "*"
    }]
  })
}
