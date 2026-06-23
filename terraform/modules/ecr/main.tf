resource "aws_ecr_repository" "this" {
  for_each = toset(var.services)

  name                 = "${var.name}/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.name}-${each.key}"
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = toset(var.services)
  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Garder les 10 dernières images, supprimer le reste"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}