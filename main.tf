# VPC

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "secure-startup-vpc"
  }
}


# Public Subnet-A

resource "aws_subnet" "public_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "public-a"
  }
}


# Public Subnet-B

resource "aws_subnet" "public_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "public-b"
  }
}


# Private Subnet-A

resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "private-db-a"
  }
}


# Private Subnet-B

resource "aws_subnet" "private_db_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "private-db-b"
  }
}


# Internet Gateway

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "secure-startup-igw"
  }
}


# Public Route Table

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}


# Public Subnet-A Route Table Association

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}


# Public Subnet-B Route Table Association

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


# Private Route Table

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private-route-table"
  }
}


# Private DB-A Route Table Association

resource "aws_route_table_association" "private_db_a" {
  subnet_id      = aws_subnet.private_db_a.id
  route_table_id = aws_route_table.private.id
}


# Private DB-B Route Table Association

resource "aws_route_table_association" "private_db_b" {
  subnet_id      = aws_subnet.private_db_b.id
  route_table_id = aws_route_table.private.id
}


# EC2 Security Group

resource "aws_security_group" "ec2" {
  name        = "ec2-security-group"
  description = "Security group for web EC2 instances"
  vpc_id      = aws_vpc.main.id

  # HTTP

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS

  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH

  ingress {
    description = "Allow SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.admin_ip}/32"]
  }

  # Outbound traffic

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2-security-group"
  }
}


# RDS Security Group

resource "aws_security_group" "rds" {
  name        = "rds-security-group"
  description = "Security group for RDS MySQL"
  vpc_id      = aws_vpc.main.id

  # MySQL

  ingress {
    description     = "Allow MySQL from EC2"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  tags = {
    Name = "rds-security-group"
  }
}


# EC2 IAM Role

resource "aws_iam_role" "ec2" {
  name = "secure-startup-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}


# EC2 S3 Read Policy

resource "aws_iam_policy" "ec2_s3_read" {
  name        = "secure-startup-ec2-s3-read"
  description = "Allow EC2 to read objects from S3"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = "arn:aws:s3:::secure-startup-assets/*"
      }
    ]
  })
}


# Attach S3 Policy to EC2 Role

resource "aws_iam_role_policy_attachment" "ec2_s3_read" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_s3_read.arn
}


# EC2 Instance Profile

resource "aws_iam_instance_profile" "ec2" {
  name = "secure-startup-ec2-profile"
  role = aws_iam_role.ec2.name
}


# Latest Amazon Linux 2023 AMI

data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}


# Web Server A

resource "aws_instance" "web_a" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.public_a.id

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.ec2.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ec2.name

  user_data = <<-EOF
    #!/bin/bash

    dnf install -y nginx

    systemctl enable nginx
    systemctl start nginx

    cat > /usr/share/nginx/html/index.html <<'HTML'
    <html>
      <head>
        <title>Secure Startup</title>
      </head>
      <body>
        <h1>Secure Startup Web Server A</h1>
        <p>Deployed using Terraform and Amazon Linux.</p>
      </body>
    </html>
    HTML
  EOF

  tags = {
    Name = "web-server-a"
  }
}

# Web Server B

resource "aws_instance" "web_b" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  subnet_id = aws_subnet.public_b.id

  associate_public_ip_address = true

  vpc_security_group_ids = [
    aws_security_group.ec2.id
  ]

  iam_instance_profile = aws_iam_instance_profile.ec2.name

  user_data = <<-EOF
    #!/bin/bash

    dnf install -y nginx

    systemctl enable nginx
    systemctl start nginx

    cat > /usr/share/nginx/html/index.html <<'HTML'
    <html>
      <head>
        <title>Secure Startup</title>
      </head>
      <body>
        <h1>Secure Startup Web Server B</h1>
        <p>Deployed using Terraform and Amazon Linux.</p>
      </body>
    </html>
    HTML
  EOF

  tags = {
    Name = "web-server-b"
  }
}
# RDS DB Subnet Group

resource "aws_db_subnet_group" "main" {
  name = "secure-startup-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_db_a.id,
    aws_subnet.private_db_b.id
  ]

  tags = {
    Name = "secure-startup-db-subnet-group"
  }
}


# RDS MySQL Database

resource "aws_db_instance" "mysql" {
  identifier = "secure-startup-mysql"

  engine         = "mysql"
  engine_version = "8.0"

  instance_class      = "db.t3.micro"
  allocated_storage   = 20
  storage_type        = "gp3"
  storage_encrypted   = true
  publicly_accessible = false
  multi_az            = true

  db_name  = "startupdb"
  username = "admin"
  password = var.db_password

  db_subnet_group_name = aws_db_subnet_group.main.name

  vpc_security_group_ids = [
    aws_security_group.rds.id
  ]

  skip_final_snapshot = true

  tags = {
    Name = "secure-startup-mysql"
  }
}

