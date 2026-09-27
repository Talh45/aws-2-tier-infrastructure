variable "vpc_cidr" {
  description = "CIDR block for the project VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "admin_ip" {
  description = "Public IP address allowed to SSH into EC2"
  type        = string
}

variable "db_password" {
  description = "Master password for the RDS MySQL database"
  type        = string
  sensitive   = true
}