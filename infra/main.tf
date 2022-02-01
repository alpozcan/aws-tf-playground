# https://registry.terraform.io/modules/terraform-aws-modules/vpc/aws/latest
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = ">= 3.11.5, < 3.12"

  name = "vpc-${var.env}"
  cidr = "10.0.0.0/16"

  azs             = ["ap-southeast-1a", "ap-southeast-1b", "ap-southeast-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = var.env == "dev" ? false : true
}

#
### SECURITY GROUPS
#
resource "aws_security_group" "alb" {
  name = "alb-${var.env}"
  vpc_id = module.vpc.vpc_id

  # might also be necessary to have a rule for plain HTTP on port 80
  ingress {
    protocol = "tcp"
    from_port = 443
    to_port = 443
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_security_group" "ecs_task" {
  name = "ecs-task-${var.env}"
  vpc_id = module.vpc.vpc_id

  ingress {
    protocol = "tcp"
    from_port = var.ecs_task_container_port
    to_port = var.ecs_task_container_port
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol = "-1"
    from_port = 0
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

#
### ECR
#
resource "aws_ecr_repository" "this" {
  name = "ecr-${var.env}"
  image_tag_mutability = "MUTABLE"  # This is necessary in order to put a latest tag on the most recent image.
}

resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description = "Expire oldest N images"
      selection = {
        tagStatus = "any"
        countType = "imageCountMoreThan"
        countNumber = 3
      }
    }]
  })
}

#
### ECS
#
# https://engineering.finleap.com/posts/2020-02-20-ecs-fargate-terraform/
resource "aws_ecs_cluster" "this" {
  name = "ecs-cluster-${var.env}"

  configuration {
    execute_command_configuration {
      kms_key_id = aws_kms_key.ecs.arn
      logging    = "OVERRIDE"

      log_configuration {
        cloud_watch_encryption_enabled = true
        cloud_watch_log_group_name     = aws_cloudwatch_log_group.ecs.name
      }
    }
  }
  # Observability
  # setting {
  #   name  = "containerInsights"
  #   value = "enabled"
  # }
}

# Observability
resource "aws_kms_key" "ecs" {  # For Cloud Watch encrption
  description         = "KMS key for the ECS CW log group"
  enable_key_rotation = true
}
resource "aws_cloudwatch_log_group" "ecs" {
  name = "ecs-log-group-${var.env}"
}

resource "aws_ecs_task_definition" "task1" {
  network_mode = "awsvpc"  # (Optional) Docker networking mode to use for the containers in the task. Valid values are none, bridge, awsvpc, and host.
  family = "task1-${var.env}"

  requires_compatibilities = ["FARGATE"]  # (Optional) Set of launch types required by the task. The valid values are EC2 and FARGATE.
  cpu = 0.25  # (Optional) Number of cpu units used by the task. If the requires_compatibilities is FARGATE this field is required.
  memory = 128  # (Optional) Amount (in MiB) of memory used by the task. If the requires_compatibilities is FARGATE this field is required.

  execution_role_arn  = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn       = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name = "container-${var.env}"
      image = "${var.ecs_task_container_image}:latest"
      essential = true
      portMappings = [{
        protocol = "tcp"
        containerPort = var.ecs_task_container_port
        hostPort = var.ecs_task_container_port
      }]
    }
  ])
}

#
### IAM
#

# Task role & policies
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role-${var.env}"
 
  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_policy" "dynamodb" {
  name        = "dynamodb-${var.env}"
  description = "Policy that allows access to DynamoDB"

  policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
       {
           "Effect": "Allow",
           "Action": [
               "dynamodb:*"
           ],
           "Resource": "*"
       }
   ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy_attachment" {
  role = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.dynamodb.arn
}

# Execution role & policies
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role-${var.env}"

  assume_role_policy = <<EOF
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Action": "sts:AssumeRole",
     "Principal": {
       "Service": "ecs-tasks.amazonaws.com"
     },
     "Effect": "Allow",
     "Sid": ""
   }
 ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy_attachment" {
  role = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
