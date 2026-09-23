output "vpc_id" {
  description = "ID of the VPC the instance runs in."
  value       = aws_vpc.main.id
}

output "instance_subnet_id" {
  description = "Subnet the instance was placed in."
  value       = aws_instance.app_server.subnet_id
}

output "instance_public_ip" {
  description = "Public IP of the EC2 instance."
  value       = aws_instance.app_server.public_ip
}
