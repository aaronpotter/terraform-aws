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
