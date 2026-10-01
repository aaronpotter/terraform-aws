# Security+ exam repo, pinned by immutable owner and repo IDs so a renamed or re-created repo can't match.
# Creates the push (main only) and deploy (environment:production only) roles.
secplus_github_subjects = ["repo:aaronpotter@9371584/securityplus-exam@1396591908"]

# Security+ exam's load balancer (Service production/security-plus-exam). Changes when the cluster is recreated.
secplus_origin_domain = "a2aa53d85c6e74736a40d316db744db2-1991571986.us-east-2.elb.amazonaws.com"

# The only hostname the Security+ exam answers to. DNS (Cloudflare) CNAMEs it to the distribution.
secplus_domain = "securityplus.turbocerts.com"
