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

  backup_retention_period    = 7
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  # Guards the data: turning off deletion_protection is a reviewed change, and a destroy still
  # leaves a final snapshot.
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.cluster_name}-postgres-final"
}
