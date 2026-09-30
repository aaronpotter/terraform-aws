# Images for the kubernetes-deploy repo, pushed by the github-actions-deploy role.
resource "aws_ecr_repository" "hello_world" {
  name                 = "hello-world"
  image_tag_mutability = "IMMUTABLE"

  # Set first so a follow-up change can delete the repository with its images (Terraform refuses to
  # destroy a non-empty repository otherwise).
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep the 20 newest tagged images. Untagged images are left alone on purpose: here they are the
# platform/attestation manifests inside multi-arch indexes (e.g. `latest`), and expiring them would
# break those tags.
resource "aws_ecr_lifecycle_policy" "hello_world" {
  repository = aws_ecr_repository.hello_world.name

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
