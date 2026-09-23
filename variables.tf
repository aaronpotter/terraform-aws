variable "instance_name" {
  description = "Value of the EC2 instance's Name tag."
  type        = string
  default     = "terraform-lab"
}

variable "instance_type" {
  description = "The EC2 instance's type."
  type        = string
  default     = "t3.micro"
}

variable "vpc_id" {
  description = "ID of the existing VPC to launch into."
  type        = string
  default     = "vpc-226c4447"
}

variable "subnet_id" {
  description = "ID of the existing subnet to launch the instance in. Must belong to var.vpc_id."
  type        = string
  default     = "subnet-1021f959"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair to attach to the instance."
  type        = string
  default     = "apotter"
}

variable "ssh_cidr" {
  description = "CIDR block allowed to reach port 22. Set this to your own address, e.g. 203.0.113.4/32. No default on purpose, so SSH is never accidentally opened to the internet."
  type        = string

  validation {
    condition     = var.ssh_cidr != "0.0.0.0/0"
    error_message = "Refusing 0.0.0.0/0: scope ssh_cidr to a specific address."
  }
}
