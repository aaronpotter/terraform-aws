variable "instance_name" {
  description = "Name prefix for the VPC and its subnet, route table and gateway."
  type        = string
  default     = "terraform-lab"
}

variable "vpc_cidr" {
  description = "CIDR block for the new VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet. Must fall inside var.vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"
}
