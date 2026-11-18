module "network" {
  source = "./modules/network"
  name   = "taskops-${var.env}"
}
