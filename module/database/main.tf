# RDS subnet group
resource "aws_db_subnet_group" "db_sub_grp" {
  name        = "app-db-sub-grp"
  subnet_ids  = [var.pri_sub1_id, var.pri_sub2_id]
  description = "subnet group for multi-az RDS"

  tags = {
    Name = "app-db"
  }
}

#RDS security group
resource "aws_security_group" "RDS-sg" {
  name        = "app-rds-sg"
  description = "RDS Security group"
  vpc_id      = var.vpc_id

  ingress {
    description     = "mysql port"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [var.bastion_sg_id, var.stage_sg, var.prod_sg]
  }
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "app-rds-sg"
  }
}

resource "aws_db_instance" "mysql_database" {
  identifier             = "pet-db"
  db_subnet_group_name   = aws_db_subnet_group.db_sub_grp.name
  vpc_security_group_ids = [aws_security_group.RDS-sg.id]
  db_name                = "petclinic"
  multi_az               = true

  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t3.micro"
  parameter_group_name = "default.mysql5.7"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  # Credentials (Initial creation - defined via variables, NOT Vault)
  username = var.db_admin_username 
  password = var.db_admin_password  

  skip_final_snapshot = true
  publicly_accessible = false
  deletion_protection = false

  # Add tags if needed
  tags = {
    Name = "pet-db"
  }
}
