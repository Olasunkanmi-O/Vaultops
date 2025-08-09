output "mysql_database_arn" {
  value       = module.database.aws_db_instance
  description = "ARN of the MySQL RDS instance"
}

output "mysql_port" {
  value       = module.database.mysql_port
  description = "Port on which MySQL is accessible"
}

output "mysql_host" {
  value       = module.database.mysql_host
  description = "Address/hostname of the MySQL database"
}

output "mysql_instance_id" {
  value       = module.database.db_instance_id
  description = "The ID of the MySQL RDS instance"
}

output "mysql_endpoint" {
  value       = module.database.db_endpoint
  description = "MySQL database connection endpoint"
}

output "mysql_subnet_group" {
  value       = module.database.db_subnet_group_name
  description = "DB subnet group used by the database"
}

output "mysql_security_group_id" {
  value       = module.database.db_security_group_id
  description = "Security group ID for the database"
}

output "app_private_route_table_id" {
  value = module.vpc.app_private_route_table_id
}

output "app_vpc_id" {
  value = module.vpc.vpc_id
}
