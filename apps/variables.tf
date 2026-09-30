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
  description = "Public hostname for the Security+ exam, e.g. securityplus.turbocerts.com. When set, an ACM certificate for it is requested (DNS validation; the validation CNAME is added by hand in Cloudflare, since that DNS zone isn't managed here). Empty disables the custom domain."
  type        = string
  default     = ""
}

variable "secplus_domain_active" {
  description = "Attach secplus_domain to the CloudFront distribution and reject any other Host. Set to true only after the certificate's validation record exists in DNS (apply waits for the certificate to be issued) and the site CNAME points at the distribution."
  type        = bool
  default     = false

  validation {
    condition     = !var.secplus_domain_active || var.secplus_domain != ""
    error_message = "secplus_domain_active requires secplus_domain."
  }
}
