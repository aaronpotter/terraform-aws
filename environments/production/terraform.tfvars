# ssh_cidr comes from the SSH_CIDR secret (TF_VAR_ssh_cidr) in CI.
instance_name      = "terraform-lab-prod"
instance_type      = "t3.micro"
vpc_cidr           = "10.1.0.0/16"
public_subnet_cidr = "10.1.1.0/24"
key_name           = "apotter"
