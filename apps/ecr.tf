# Images for the kubernetes-deploy repo, pushed by the github-actions-deploy role.
resource "aws_ecr_repository" "hello_world" {
  name                 = "hello-world"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}
