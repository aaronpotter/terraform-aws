variable "origin_domain" {
  description = "Hostname of the load balancer Kubernetes created for Service production/hello-world. Changes whenever the cluster is recreated: kubectl -n production get svc hello-world -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
  type        = string

  validation {
    condition     = endswith(var.origin_domain, ".elb.amazonaws.com")
    error_message = "origin_domain must be the Service's load balancer hostname (*.elb.amazonaws.com)."
  }
}
