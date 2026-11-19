variable "name" {
  description = "Préfixe des noms de ressources"
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  description = "Sous-réseau public où placer l'instance"
  type        = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ssh_cidr" {
  description = "Seule IP autorisée en SSH (x.x.x.x/32) ; null = pas d'accès SSH"
  type        = string
  default     = null

  validation {
    condition     = var.ssh_cidr == null ? true : (can(cidrhost(var.ssh_cidr, 0)) && endswith(var.ssh_cidr, "/32"))
    error_message = "ssh_cidr doit être une seule adresse IP au format x.x.x.x/32."
  }
}

variable "ssh_public_key" {
  description = "Clé publique SSH de l'administrateur ; null = pas de clé"
  type        = string
  default     = null
}

variable "app_image" {
  description = "Image Docker de l'API"
  type        = string
}
