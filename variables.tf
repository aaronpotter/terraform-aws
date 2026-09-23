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

variable "vpc_cidr" {
  description = "CIDR block for the new VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet the instance runs in. Must fall inside var.vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"
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
