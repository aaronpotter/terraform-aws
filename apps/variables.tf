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
