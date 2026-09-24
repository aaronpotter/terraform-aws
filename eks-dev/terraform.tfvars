# Committed. admin_cidr comes from TF_VAR_admin_cidr (ADMIN_CIDR variable in CI) so an address never lands in the repo.
cluster_name       = "apotterlab"
node_instance_type = "t3.medium"
node_desired_size  = 1
node_min_size      = 1
node_max_size      = 2
node_capacity_type = "ON_DEMAND"
