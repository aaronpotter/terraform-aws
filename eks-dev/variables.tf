variable "cluster_name" {
  description = "Name of the EKS cluster, also used to prefix its VPC, subnets, and IAM roles."
  type        = string
  default     = "apotterlab"
}

variable "kubernetes_version" {
  description = "EKS control plane version. null takes the EKS default at creation; set it explicitly to upgrade."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for the cluster VPC. Must not overlap the lab VPCs (10.0.0.0/16, 10.1.0.0/16)."
  type        = string
  default     = "10.2.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets, one per AZ. EKS requires at least two AZs."
  type        = list(string)
  default     = ["10.2.1.0/24", "10.2.2.0/24"]

  validation {
    condition     = length(var.public_subnet_cidrs) >= 2
    error_message = "EKS needs subnets in at least two availability zones."
  }
}

variable "admin_cidr" {
  description = "CIDR block allowed to reach the EKS API's public endpoint, e.g. 203.0.113.4/32. No default on purpose; supply via TF_VAR_admin_cidr."
  type        = string

  validation {
    condition     = var.admin_cidr != "0.0.0.0/0"
    error_message = "Refusing 0.0.0.0/0: scope admin_cidr to a specific address."
  }
}

variable "cluster_admin_arns" {
  description = "IAM principal ARNs granted cluster-admin through EKS access entries."
  type        = list(string)
  default     = ["arn:aws:iam::549610932637:user/github-actions-terraform"]
}

variable "node_instance_type" {
  description = "Instance type for the managed node group."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 1
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}
