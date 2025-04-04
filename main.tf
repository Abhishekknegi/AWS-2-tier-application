provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "demo_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "demo"
  }
}

# Subnets
resource "aws_subnet" "demo_subnet_1" {
  vpc_id            = aws_vpc.demo_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "demo1"
  }
}

resource "aws_subnet" "demo_subnet_2" {
  vpc_id            = aws_vpc.demo_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "demo2"
  }
}

# Internet Gateway and Route Table for public access
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.demo_vpc.id
}

resource "aws_route_table" "demo_route_table" {
  vpc_id = aws_vpc.demo_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.demo_subnet_1.id
  route_table_id = aws_route_table.demo_route_table.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.demo_subnet_2.id
  route_table_id = aws_route_table.demo_route_table.id
}

# Security Group
resource "aws_security_group" "demo_sg" {
  vpc_id = aws_vpc.demo_vpc.id
  description = "Allow traffic"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "demo"
  }
}

# RDS and Subnet Group
resource "aws_db_subnet_group" "demo_subnet_group" {
  name       = "demo-subnet-group"
  subnet_ids = [aws_subnet.demo_subnet_1.id, aws_subnet.demo_subnet_2.id]
  tags = {
    Name = "demo"
  }
}

resource "aws_db_instance" "demo_db" {
  identifier              = "demo-db"
  allocated_storage       = 20
  storage_type            = "gp2"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t2.micro"
  db_name                 = "demo"
  username                = "admin"
  password                = "password"
  publicly_accessible     = true
  vpc_security_group_ids  = [aws_security_group.demo_sg.id]
  db_subnet_group_name    = aws_db_subnet_group.demo_subnet_group.name
  skip_final_snapshot     = true
  tags = {
    Name = "demo"
  }
}

# Launch Template
resource "aws_launch_template" "demo_launch_template" {
  name          = "demo-launch-template"
  image_id      = "ami-053b0d53c279acc90"
  instance_type = "t2.micro"
  key_name      = "my-key"

  user_data = base64encode(<<-EOF
    #!/bin/bash
    sudo su
    apt update -y
    apt install apache2 -y
    apt install php libapache2-mod-php php-mysql -y
    apt install mysql-client -y
    apt install rar unrar zip unzip -y
    apt install git -y
    cd /var/www/html/
    git clone https://github.com/Vimal007Vimal/AWS-2-tier-application.git
    rm -f index.html
    cd AWS-2-tier-application
    mv * /var/www/html/
    cd ..
    rmdir AWS-2-tier-application
    systemctl restart apache2
    systemctl enable apache2
  EOF
  )
}

# ALB
resource "aws_lb" "demo_alb" {
  name               = "demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo_sg.id]
  subnets            = [aws_subnet.demo_subnet_1.id, aws_subnet.demo_subnet_2.id]
}

resource "aws_lb_target_group" "demo_tg" {
  name     = "demo-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demo_vpc.id
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "demo_listener" {
  load_balancer_arn = aws_lb.demo_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo_tg.arn
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "demo_asg" {
  desired_capacity     = 2
  max_size             = 3
  min_size             = 1
  vpc_zone_identifier  = [aws_subnet.demo_subnet_1.id, aws_subnet.demo_subnet_2.id]
  target_group_arns    = [aws_lb_target_group.demo_tg.arn]

  launch_template {
    id      = aws_launch_template.demo_launch_template.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "demo-instance"
    propagate_at_launch = true
  }
}

# Monitoring
resource "aws_sns_topic" "demo_sns_topic" {
  name = "demo"
}

resource "aws_sns_topic_subscription" "demo_sns_subscription" {
  topic_arn = aws_sns_topic.demo_sns_topic.arn
  protocol  = "email"
  endpoint  = "your-email@example.com"
}

resource "aws_cloudwatch_metric_alarm" "demo_alarm" {
  alarm_name          = "demo-alarm"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 1
  alarm_actions       = [aws_sns_topic.demo_sns_topic.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.demo_asg.name
  }
}

output "alb_dns_name" {
  value = aws_lb.demo_alb.dns_name
}
