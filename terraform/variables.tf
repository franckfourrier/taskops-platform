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
