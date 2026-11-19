variable "name" {
  description = "Préfixe des noms de ressources"
  type        = string
}

variable "instance_id" {
  description = "Instance EC2 surveillée"
  type        = string
}

variable "cpu_threshold" {
  description = "Seuil d'alerte CPU (%)"
  type        = number
  default     = 80
}

variable "alert_email" {
  description = "Adresse e-mail des alertes ; null ou vide = pas d'abonnement"
  type        = string
  default     = null
}
