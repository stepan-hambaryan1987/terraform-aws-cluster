terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.13.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {}


resource "aws_vpc" "main" {
  cidr_block = var.vpc_cider

  tags = {
    Name        = "${var.env}-vpc"
    Environment = var.env
  }
}

resource "aws_security_group" "web_sg" {
  name        = "web-new-sg"
  description = "Allow SSH, HTTP, HTTPS"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name        = "web-sg"
    Environment = var.env
  }
}

resource "aws_security_group_rule" "ingress_rules" {
  count             = length(var.ports)
  type              = "ingress"
  from_port         = var.ports[count.index]
  to_port           = var.ports[count.index]
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web_sg.id
}

resource "aws_security_group_rule" "egress_rule" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web_sg.id
}

resource "aws_security_group_rule" "icmp_egress_rule" {
  type              = "ingress"
  from_port         = 8
  to_port           = -1
  protocol          = "icmp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web_sg.id
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.env}-IGW"
    Environment = var.env
  }
}

resource "aws_subnet" "public-subnet" {
  count                   = length(var.public_subnet_ciders)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_ciders, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.env}-public-subnet-${count.index + 1}"
    Environment = var.env
  }
}

resource "aws_route_table" "public-rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name        = "${var.env}-public-rt"
    Environment = var.env
  }
}

resource "aws_route_table_association" "pub-rt" {
  count          = length(aws_subnet.public-subnet[*].id)
  subnet_id      = element(aws_subnet.public-subnet[*].id, count.index)
  route_table_id = aws_route_table.public-rt.id
}


resource "aws_subnet" "private-subnet" {
  count             = length(var.private_subnet_ciders)
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_ciders, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name        = "${var.env}-private-subnet-${count.index + 1}"
    Environment = var.env
  }
}


resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name        = "${var.env}-nat-eip"
    Environment = var.env
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public-subnet[0].id
  depends_on    = [aws_internet_gateway.igw]

  tags = {
    Name        = "${var.env}-nat-gateway"
    Environment = var.env
  }
}

resource "aws_route_table" "private-rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name        = "${var.env}-private-rt"
    Environment = var.env
  }
}

resource "aws_route_table_association" "priv-rt" {
  count          = length(aws_subnet.private-subnet[*].id)
  subnet_id      = aws_subnet.private-subnet[count.index].id
  route_table_id = aws_route_table.private-rt.id
}


# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.env}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cluster_AmazonEKSServicePolicy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}


# Node Group IAM Role
resource "aws_iam_role" "eks_node_role" {
  name = "${var.env}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# eks cluster
resource "aws_eks_cluster" "eks_cluster" {
  name     = "${var.env}-eks"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.30"

  vpc_config {
    subnet_ids             = concat(aws_subnet.public-subnet[*].id, aws_subnet.private-subnet[*].id)
    endpoint_public_access = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.eks_cluster_AmazonEKSServicePolicy
  ]
}

# ssh key pear
resource "aws_key_pair" "eks_key" {
  key_name   = "eks-key"                 # name in AWS
  public_key = file("~/.ssh/id_rsa.pub") # use your local SSH public key
}


# eks node group
resource "aws_eks_node_group" "eks_nodes" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.env}-eks-nodes"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = aws_subnet.private-subnet[*].id # use private subnets for workers

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  instance_types = ["t3.small"]

  remote_access {
    ec2_ssh_key               = "eks-key" # must create/upload this in AWS first
    source_security_group_ids = [aws_security_group.web_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.eks_node_AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.eks_node_AmazonEKS_CNI_Policy
  ]
}





#create ECS
# provider "aws" {
#   region = "us-east-1"
# }

# variable "env" {
#   default = "dev"
# }

# # 1. ECS Cluster
# resource "aws_ecs_cluster" "this" {
#   name = "${var.env}-ecs-cluster"
# }

# # 2. Task Definition (example: nginx container)
# resource "aws_ecs_task_definition" "nginx" {
#   family                   = "${var.env}-nginx-task"
#   network_mode             = "awsvpc"
#   requires_compatibilities = ["FARGATE"]
#   cpu                      = "256"
#   memory                   = "512"
#   execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

#   container_definitions = jsonencode([
#     {
#       name      = "nginx"
#       image     = "nginx:latest"
#       essential = true
#       portMappings = [
#         {
#           containerPort = 80
#           hostPort      = 80
#           protocol      = "tcp"
#         }
#       ]
#     }
#   ])
# }

# # 3. IAM Role for ECS tasks
# resource "aws_iam_role" "ecs_task_execution_role" {
#   name = "${var.env}-ecsTaskExecutionRole"

#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Action    = "sts:AssumeRole"
#       Effect    = "Allow"
#       Principal = { Service = "ecs-tasks.amazonaws.com" }
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
#   role       = aws_iam_role.ecs_task_execution_role.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
# }

# # 4. Security Group
# resource "aws_security_group" "ecs_sg" {
#   vpc_id = aws_vpc.main.id

#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

# # 5. Load Balancer
# resource "aws_lb" "ecs_alb" {
#   name               = "${var.env}-ecs-alb"
#   internal           = false
#   load_balancer_type = "application"
#   security_groups    = [aws_security_group.ecs_sg.id]
#   subnets            = aws_subnet.public-subnet[*].id
# }

# resource "aws_lb_target_group" "ecs_tg" {
#   name        = "${var.env}-ecs-tg"
#   port        = 80
#   protocol    = "HTTP"
#   vpc_id      = aws_vpc.main.id
#   target_type = "ip"
# }

# resource "aws_lb_listener" "ecs_listener" {
#   load_balancer_arn = aws_lb.ecs_alb.arn
#   port              = "80"
#   protocol          = "HTTP"

#   default_action {
#     type             = "forward"
#     target_group_arn = aws_lb_target_group.ecs_tg.arn
#   }
# }

# # 6. ECS Service (keeps containers running)
# resource "aws_ecs_service" "nginx_service" {
#   name            = "${var.env}-nginx-service"
#   cluster         = aws_ecs_cluster.this.id
#   task_definition = aws_ecs_task_definition.nginx.arn
#   launch_type     = "FARGATE"
#   desired_count   = 2

#   network_configuration {
#     subnets         = aws_subnet.private-subnet[*].id
#     security_groups = [aws_security_group.ecs_sg.id]
#     assign_public_ip = false
#   }

#   load_balancer {
#     target_group_arn = aws_lb_target_group.ecs_tg.arn
#     container_name   = "nginx"
#     container_port   = 80
#   }

#   depends_on = [aws_lb_listener.ecs_listener]
# }













# resource "aws_route_table" "private-rt" {
#   count  = length(var.private_subnet_ciders)
#   vpc_id = aws_vpc.main.id

#   route {
#     cidr_block     = "0.0.0.0/0"
#     nat_gateway_id = aws_nat_gateway.nat[count.index].id
#   }

#   tags = {
#     Name        = "${var.env}-private-rt-${count.index + 1}"
#     Environment = var.env
#   }
# }

# resource "aws_route_table_association" "priv-rt" {
#   count          = length(aws_subnet.private-subnet[*].id)
#   subnet_id      = element(aws_subnet.private-subnet[*].id, count.index)
#   route_table_id = aws_route_table.private-rt[count.index].id
# }

# resource "aws_eip" "el-ip" {
#   count  = length(var.private_subnet_ciders)
#   domain = "vpc"

#   tags = {
#     Name        = "${var.env}-el-ip-${count.index + 1}"
#     Environment = var.env
#   }
# }

# resource "aws_nat_gateway" "nat" {
#   count         = length(var.private_subnet_ciders)
#   allocation_id = aws_eip.el-ip[count.index].id
#   subnet_id     = element(aws_subnet.public-subnet[*].id, count.index)

#   tags = {
#     Name = "${var.env}-nat-gateway-${count.index + 1}"
#   }

#   # To ensure proper ordering, it is recommended to add an explicit dependency
#   # on the Internet Gateway for the VPC.
#   depends_on = [aws_internet_gateway.igw]
# }
