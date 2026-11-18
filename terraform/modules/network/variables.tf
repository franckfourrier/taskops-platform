variable "name" {
  description = "Préfixe des noms de ressources (ex. taskops-dev)"
  type        = string
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
