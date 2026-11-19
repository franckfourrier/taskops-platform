variable "region" {
  description = "Région AWS"
  type        = string
  default     = "eu-west-3"
}

variable "env" {
  description = "Environnement (dev, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env doit valoir dev ou prod."
  }
}

variable "vpc_cidr" {
  description = "Plage d'adresses du VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "Plage du sous-réseau public"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "Plage du sous-réseau privé"
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.micro"
}

variable "ssh_cidr" {
  description = "IP autorisée en SSH (x.x.x.x/32) — null = pas de SSH (défaut, et en CI)"
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "Clé publique SSH — fournie via TF_VAR_ssh_public_key"
  type        = string
  default     = null
}

variable "app_image" {
  description = "Image Docker de l'API TaskOps"
  type        = string
  default     = "ghcr.io/franckfourrier/taskops-api:0.1.1"
}
