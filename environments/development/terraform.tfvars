# ssh_cidr comes from the SSH_CIDR secret (TF_VAR_ssh_cidr) in CI.
# instance_name stays "terraform-lab" to match the running lab; changing it renames and replaces the security group.
instance_name      = "terraform-lab"
instance_type      = "t3.micro"
vpc_cidr           = "10.0.0.0/16"
public_subnet_cidr = "10.0.1.0/24"
key_name           = "apotter"
