module "network" {
  source = "./modules/network"
  name   = "taskops-${var.env}"
}

module "compute" {
  source         = "./modules/compute"
  name           = "taskops-${var.env}"
  vpc_id         = module.network.vpc_id
  subnet_id      = module.network.public_subnet_id
  instance_type  = var.instance_type
  ssh_cidr       = var.ssh_cidr
  ssh_public_key = var.ssh_public_key
  app_image      = var.app_image
}
