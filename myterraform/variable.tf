variable "env" {
  description = "for resourses names"
  type        = string
  default     = "dev"
}

variable "vpc_cider" {
  description = "cider-block for vpc"
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_ciders" {
  description = "ciders for public subnets"
  type        = list(string)
  default = [
    "10.10.0.0/24",
    "10.10.1.0/24",
    #"10.10.2.0/24"
  ]
}

variable "private_subnet_ciders" {
  description = "ciders for private subnets"
  type        = list(string)
  default = [
    "10.10.10.0/24",
    "10.10.11.0/24",
    #"10.10.12.0/24"
  ]
}

variable "ports" {
  default = [22, 80, 443]
}