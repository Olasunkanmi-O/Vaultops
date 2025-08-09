output "aws_db_instance" {
  value = aws_db_instance.mysql_database.arn
}

output "mysql_port" {
  description = "The port of the RDS MySQL database."
  value       = aws_db_instance.mysql_database.port
}


output "mysql_host" {
  description = "The hostname (address) of the RDS MySQL database."
  value       = aws_db_instance.mysql_database.address
}

output "db_instance_id" {
  value       = aws_db_instance.mysql_database.id
  description = "The ID of the RDS instance"
}

output "db_endpoint" {
  value       = aws_db_instance.mysql_database.endpoint
  description = "RDS endpoint address"
}

output "db_subnet_group_name" {
  value       = aws_db_subnet_group.db_sub_grp.name
  description = "Name of the DB subnet group"
}

output "db_security_group_id" {
  value       = aws_security_group.RDS-sg.id
  description = "The security group ID of the database"
}
