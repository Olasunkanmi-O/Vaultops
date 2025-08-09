output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "pub_sub1_id" {
  value = aws_subnet.pub_sub1.id
}

output "pub_sub2_id" {
  value = aws_subnet.pub_sub2.id
}

output "pri_sub1_id" {
  value = aws_subnet.pri_sub1.id
}
output "pri_sub2_id" {
  value = aws_subnet.pri_sub2.id
}

output "app_private_route_table_id" {
  value       = aws_route_table.pri_rt.id
  description = "Private Route Table ID for the App VPC"
}

output "app_public_route_table_id" {
  value       = aws_route_table.pub_rt.id
  description = "Public Route Table ID for the App VPC"
}

output "cidr_block" {
  value = aws_vpc.vpc.cidr_block
}