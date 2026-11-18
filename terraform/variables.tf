variable "region" {
  description = "Région AWS"
  type        = string
  default     = "eu-west-3"
}

variable "env" {
  description = "Environnement (dev, prod)"
  type        = string
  default     = "dev"
}

variable "instance_type" {
  description = "Type d'instance EC2"
  type        = string
  default     = "t3.micro"
}

variable "ssh_cidr" {
  description = "IP autorisée en SSH (x.x.x.x/32) — fournie via TF_VAR_ssh_cidr, jamais committée"
  type        = string
}

variable "ssh_public_key" {
  description = "Clé publique SSH — fournie via TF_VAR_ssh_public_key"
  type        = string
}

variable "app_image" {
  description = "Image Docker de l'API TaskOps"
  type        = string
  default     = "ghcr.io/franckfourrier/taskops-api:0.1.1"
}
