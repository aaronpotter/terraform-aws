# PostgreSQL for workloads on the apotterlab cluster. Private subnets, reachable only from the
# cluster's security group, and independent of var.enabled: turning the cluster off keeps the data.

# ------------------------------------------------------------------
# Private subnets: no route to the internet gateway
# ------------------------------------------------------------------

resource "aws_subnet" "db" {
  count = length(var.db_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.cluster_name}-db-${count.index}"
  }
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-db"
  }
}

resource "aws_route_table_association" "db" {
  count = length(aws_subnet.db)

  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.cluster_name}-db"
  subnet_ids = aws_subnet.db[*].id
}

# ------------------------------------------------------------------
# Security group: 5432 from the cluster only
# ------------------------------------------------------------------

resource "aws_security_group" "db" {
  name        = "${var.cluster_name}-db"
  description = "PostgreSQL for ${var.cluster_name}; ingress from the EKS cluster security group only"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.cluster_name}-db"
  }
}

# Nodes and pods (VPC CNI) use the EKS-managed cluster security group. While the cluster is off,
# nothing can connect.
resource "aws_vpc_security_group_ingress_rule" "db_from_cluster" {
  count = var.enabled ? 1 : 0

  security_group_id            = aws_security_group.db.id
  referenced_security_group_id = aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS nodes and pods"
}

# ------------------------------------------------------------------
# Database
# ------------------------------------------------------------------

resource "aws_db_instance" "main" {
  identifier     = "${var.cluster_name}-postgres"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  # RDS generates the password and keeps it in Secrets Manager; it never touches state or the repo.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  multi_az               = false

  # The AWS Free plan caps automated backups at 1 day (7 fails with FreeTierRestrictionError).
  # Raise this after upgrading the account plan.
  backup_retention_period    = 1
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  # Guards the data: turning off deletion_protection is a reviewed change, and a destroy still
  # leaves a final snapshot.
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.cluster_name}-postgres-final"
}

# ------------------------------------------------------------------
# Keep the database stopped while it is unused
# ------------------------------------------------------------------

# RDS starts a stopped instance again after 7 days. This stops it again right after that automatic
# start (RDS-EVENT-0154 for instances, 0153 for clusters). A start you do yourself raises a different
# event, so reusing the database is unaffected. Set db_auto_stop = false to remove the guard.

data "archive_file" "rds_restop" {
  count = var.db_auto_stop ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/rds-restop/lambda_function.py"
  output_path = "${path.module}/build/rds-restop.zip"
}

resource "aws_iam_role" "rds_restop" {
  count = var.db_auto_stop ? 1 : 0

  name = "${var.cluster_name}-rds-restop"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "rds_restop" {
  count = var.db_auto_stop ? 1 : 0

  name = "stop-${var.cluster_name}-postgres"
  role = aws_iam_role.rds_restop[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds:DescribeDBInstances", "rds:StopDBInstance"]
        Resource = aws_db_instance.main.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.rds_restop[0].arn}:*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "rds_restop" {
  count = var.db_auto_stop ? 1 : 0

  name              = "/aws/lambda/${var.cluster_name}-rds-restop"
  retention_in_days = 30
}

resource "aws_lambda_function" "rds_restop" {
  count = var.db_auto_stop ? 1 : 0

  function_name    = "${var.cluster_name}-rds-restop"
  role             = aws_iam_role.rds_restop[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.13"
  architectures    = ["x86_64"]
  memory_size      = 128
  timeout          = 900
  filename         = data.archive_file.rds_restop[0].output_path
  source_code_hash = data.archive_file.rds_restop[0].output_base64sha256

  environment {
    variables = {
      DB_INSTANCE_ID = aws_db_instance.main.identifier
    }
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.rds_restop[0].name
  }
}

resource "aws_cloudwatch_event_rule" "rds_auto_start" {
  count = var.db_auto_stop ? 1 : 0

  name        = "${var.cluster_name}-rds-auto-start"
  description = "RDS restarted ${var.cluster_name}-postgres after its maximum 7 days stopped"

  event_pattern = jsonencode({
    source      = ["aws.rds"]
    detail-type = ["RDS DB Instance Event"]
    detail = {
      SourceIdentifier = [aws_db_instance.main.identifier]
      EventID          = ["RDS-EVENT-0153", "RDS-EVENT-0154"]
    }
  })
}

resource "aws_cloudwatch_event_target" "rds_restop" {
  count = var.db_auto_stop ? 1 : 0

  rule = aws_cloudwatch_event_rule.rds_auto_start[0].name
  arn  = aws_lambda_function.rds_restop[0].arn
}

resource "aws_lambda_permission" "rds_restop" {
  count = var.db_auto_stop ? 1 : 0

  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rds_restop[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.rds_auto_start[0].arn
}
