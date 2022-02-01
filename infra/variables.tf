variable "env" {
  description = "A short name to differentiate between environments. Valid options: dev, prod."
  type = string
}

variable "ecs_task_container_port" {
  type = number
  default = 80
}

variable "ecs_task_container_image" {
  description = "Image name to run in ECS task containers (without the image tag)"
  type = string
  default = "busybox"
}

variable "ecs_task_container_environment" {
  type = string
  default = "dev"
}
