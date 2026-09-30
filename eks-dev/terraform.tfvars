# Committed.

# The on/off switch: false removes the cluster and node group (~$3.10/day), true brings them back.
# Turning off takes two applies: app_namespace_enabled = false first (deletes the namespace and its
# load balancers while the cluster is up), then enabled = false. To turn on, set BOTH to true.
enabled = false

app_namespace_enabled = false

cluster_name = "apotterlab"
# Free plan accounts reject non-free-tier types (t3.medium fails with InvalidParameterCombination).
# t3.small: 2 GiB, 11 pods max; 4 go to system pods.
node_instance_type = "t3.small"
node_desired_size  = 1
node_min_size      = 1
node_max_size      = 2
node_capacity_type = "ON_DEMAND"
