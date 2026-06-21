output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_compute_subnet_ids" {
  value = aws_subnet.private_compute[*].id
}

output "private_data_subnet_ids" {
  value = aws_subnet.private_data[*].id
}