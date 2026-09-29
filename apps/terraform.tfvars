# Committed. The load balancer hostname is public and changes when the eks-dev cluster is recreated.
origin_domain = "a5f29f68b09f64508bd20c3c6ac6f7a7-1942149347.us-east-2.elb.amazonaws.com"

# Security+ exam repo, pinned by immutable owner and repo IDs so a renamed or re-created repo can't match.
# Creates the push (main only) and deploy (environment:production only) roles.
secplus_github_subjects = ["repo:aaronpotter@9371584/securityplus-exam@1396591908"]
