output "instance_id" {
  description = "ID of the EC2 instance hosting the application"
  value       = aws_instance.application_server.id
}

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.application_server.public_ip
}

