# CI role for the aaronpotter/kubernetes-deploy repo: pushes images to ECR, reads EKS cluster info,
# and (via an access entry in eks-dev/) deploys into the production namespace.

locals {
  # Immutable subject format: owner and repo IDs pinned, so a renamed or re-created repo can't match.
  # Only the two jobs that use this role: build-push (push to main, no environment) and
  # deploy-production (environment: production).
  github_deploy_subjects = [
    "repo:aaronpotter@9371584/kubernetes-deploy@1393066535:ref:refs/heads/main",
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

resource "aws_iam_role_policy_attachment" "github_deploy_ecr" {
  role       = aws_iam_role.github_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
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
# Push-only role for the build job (stage 1 of splitting github-actions-deploy)
# ------------------------------------------------------------------
# build-push runs on every push to main and only needs to push to hello-world. Once the
# kubernetes-deploy workflow's build job assumes this role, github-actions-deploy drops the
# ref:refs/heads/main subject and its ECR access (stage 2), so no main-branch job can touch the cluster.

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
