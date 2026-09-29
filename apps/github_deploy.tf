# CI role for the aaronpotter/kubernetes-deploy repo's deploy-production job: reads EKS cluster info
# and (via an access entry in eks-dev/) runs helm in the production namespace. No ECR access; the
# build job pushes with github-actions-ecr-push, and nodes pull images with the node role.

locals {
  # Immutable subject format: owner and repo IDs pinned, so a renamed or re-created repo can't match.
  # Only the production environment, so no plain main-branch job can reach the cluster.
  github_deploy_subjects = [
    "repo:aaronpotter@9371584/kubernetes-deploy@1393066535:environment:production",
  ]
}

resource "aws_iam_role" "github_deploy" {
  name = "github-actions-deploy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = local.github_deploy_subjects
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_deploy_eks_describe" {
  name = "eks-describe"
  role = aws_iam_role.github_deploy.id

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
# Push-only role for the build job
# ------------------------------------------------------------------
# build-push runs on every push to main and only needs to push to hello-world. It has no EKS access;
# deploying is github-actions-deploy's job, trusted only for environment:production.

resource "aws_iam_role" "github_ecr_push" {
  name        = "github-actions-ecr-push"
  description = "kubernetes-deploy build job: push images to the hello-world ECR repository only."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${local.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:aaronpotter@9371584/kubernetes-deploy@1393066535:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_ecr_push" {
  name = "push-hello-world"
  role = aws_iam_role.github_ecr_push.id

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
        Sid    = "PushAndInspectHelloWorld"
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
        Resource = aws_ecr_repository.hello_world.arn
      },
    ]
  })
}
