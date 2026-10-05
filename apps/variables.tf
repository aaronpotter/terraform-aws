variable "secplus_origin_domain" {
  description = "Hostname of the load balancer Kubernetes created for Service production/security-plus-exam. Empty until the first helm install; then: kubectl -n production get svc security-plus-exam -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'. Changes whenever the cluster is recreated."
  type        = string
  default     = ""

  validation {
    condition     = var.secplus_origin_domain == "" || endswith(var.secplus_origin_domain, ".elb.amazonaws.com")
    error_message = "secplus_origin_domain must be empty or the Service's load balancer hostname (*.elb.amazonaws.com)."
  }
}

variable "secplus_github_subjects" {
  description = "GitHub OIDC subject prefixes of the Security+ exam repo, pinned by immutable IDs, e.g. [\"repo:aaronpotter@<owner id>/<repo>@<repo id>\"]. Empty until the repo exists on GitHub; the CI roles are created only when set."
  type        = list(string)
  default     = []
}

variable "secplus_domain" {
  description = "The only hostname the Security+ exam is served on, e.g. securityplus.turbocerts.com. It becomes the distribution's alias (using the imported *.turbocerts.com certificate), and a CloudFront Function returns 403 for any other Host, including the default *.cloudfront.net name. Empty serves the default cloudfront.net name with no restriction."
  type        = string
  default     = ""
}

variable "secplus_apex_domain" {
  description = "Apex hostname served by a second distribution to the same origin, e.g. turbocerts.com (certificate: the imported apex cert). Required: the apex distribution always exists."
  type        = string
  default     = ""
}

variable "awsdevops_github_subjects" {
  description = "GitHub OIDC subject prefixes of the AWS DevOps exam repo, pinned by immutable IDs, e.g. [\"repo:aaronpotter@<owner id>/<repo>@<repo id>\"]. The CI roles are created only when set."
  type        = list(string)
  default     = []
}

variable "awsdevops_origin_domain" {
  description = "Hostname of the load balancer Kubernetes created for Service production/aws-devops-exam. Empty until the first helm install; then: kubectl -n production get svc aws-devops-exam -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'. Changes whenever the cluster is recreated."
  type        = string
  default     = ""

  validation {
    condition     = var.awsdevops_origin_domain == "" || endswith(var.awsdevops_origin_domain, ".elb.amazonaws.com")
    error_message = "awsdevops_origin_domain must be empty or the Service's load balancer hostname (*.elb.amazonaws.com)."
  }
}

variable "awsdevops_domain" {
  description = "The only hostname the AWS DevOps exam is served on, e.g. awsdevops.turbocerts.com. It becomes the distribution's alias (using the imported *.turbocerts.com certificate), and a CloudFront Function returns 403 for any other Host, including the default *.cloudfront.net name. Empty serves the default cloudfront.net name with no restriction."
  type        = string
  default     = ""
}
