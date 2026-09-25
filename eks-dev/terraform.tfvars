# Committed. admin_cidr comes from TF_VAR_admin_cidr (ADMIN_CIDR variable in CI) so an address never lands in the repo.

# The on/off switch: false removes the cluster and node group (~$3.10/day), true brings them back.
enabled = true

cluster_name = "apotterlab"
# Free plan accounts reject non-free-tier types (t3.medium fails with InvalidParameterCombination).
# t3.small: 2 GiB, 11 pods max; 4 go to system pods.
node_instance_type = "t3.small"
node_desired_size  = 1
node_min_size      = 1
node_max_size      = 2
node_capacity_type = "ON_DEMAND"
