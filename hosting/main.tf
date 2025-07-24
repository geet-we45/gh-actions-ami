
locals {
  app_name                  = "flask-app"
  app_port                  = 5050
  key_pair_name            = null  # Set to your key pair name if needed
  allowed_ssh_cidr_blocks  = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]  # Private networks only
  allowed_http_cidr_blocks = ["0.0.0.0/0"]  # Public access to app
  enable_detailed_monitoring = false
  root_volume_size         = 20
  create_elastic_ip        = true
  
  instance_type = var.environment == "prod" ? "t3.medium" : (var.environment == "staging" ? "t3.small" : "t3.micro")
}

# Get the specified AMI
data "aws_ami" "selected_ami" {
  most_recent = true
  owners      = [var.custom_ami_owner]

  filter {
    name   = "name"
    values = [var.custom_ami_name]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "app-vpc" {
  cidr_block           = "10.0.0.0/16"

  tags = {
    Name = "app-vpc"
  }
}


# Get default subnet
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_subnet" "public-subnet" {
  cidr_block        = "10.0.0.0/24"
  vpc_id            = aws_vpc.app-vpc.id
  availability_zone = "us-west-2a"

  tags = {
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "private-subnet" {
  cidr_block        = "10.0.1.0/24"
  vpc_id            = aws_vpc.app-vpc.id
  availability_zone = "us-west-2b"

  tags = {
    Name = "Private Subnet"
  }
}

resource "aws_route_table_association" "public-subnet" {
  route_table_id = aws_route_table.public-route.id
  subnet_id      = aws_subnet.public-subnet.id
}

resource "aws_route_table_association" "private-subnet" {
  subnet_id      = aws_subnet.private-subnet.id
  route_table_id = aws_route_table.private-route.id
}



# Create security group for the application
resource "aws_security_group" "app_sg" {
  name = "app-sg-${random_string.random_name.result}"
  description = "Security group for application"
  vpc_id      = aws_vpc.app-vpc.id


  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Change to local.allowed_ssh_cidr_blocks for restricted access
    description = "SSH access"
  }
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Flask application access"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_role" "app_role" {
  name = "app-role-${random_string.random_name.result}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_ssm" {
  role       = aws_iam_role.app_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "app_profile" {
  name = "app-profile-${random_string.random_name.result}"
  role        = aws_iam_role.app_role.name
}

locals {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    app_port = local.app_port
  }))
}

resource "tls_private_key" "app_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ssh" {
  key_name   = format("app_key-%s", random_string.random_name.result)
  public_key = tls_private_key.app_key.public_key_openssh
}

resource "local_file" "aws_key" {
  content  = tls_private_key.app_key.private_key_pem
  filename = "app_key.pem"
}

resource "aws_instance" "application_server" {
  depends_on = [
    aws_security_group.logging-SG
  ]
  ami                         = "ami-0528a5175983e7f28"
  instance_type               = "t2.micro"
  iam_instance_profile        = aws_iam_instance_profile.app_profile.name
  key_name                    = aws_key_pair.ssh.key_name
  subnet_id                   = aws_subnet.public-subnet.id
  associate_public_ip_address = true
  user_data                   = file("user_data.sh")
  vpc_security_group_ids      = [aws_security_group.app_sg.id]

  tags = {
    Name = "AppServer-${random_string.random_name.result}"
  }

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = aws_vpc.app-vpc.id

  tags = {
    Name = "VPC Gateway"
  }
}

resource "aws_route_table" "public-route" {
  vpc_id = aws_vpc.app-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gateway.id
  }

  tags = {
    Name = "Public Subnet Route"
  }
}

resource "aws_route_table" "private-route" {
  vpc_id = aws_vpc.app-vpc.id
  tags = {
    Name = "Private"
  }
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.public-subnet.id
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"
}
resource "aws_nat_gateway" "public-subnet" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public-subnet.id
  depends_on    = [aws_internet_gateway.gateway]
}
