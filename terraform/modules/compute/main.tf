# Module compute : une instance EC2 publique qui fait tourner l'image TaskOps (projet 1).

# Dernière AMI Amazon Linux 2023 (x86_64) publiée par AWS
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app-sg"
  description = "TaskOps : HTTP ouvert, SSH limite a une seule IP"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-app-sg" }
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP public"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.app.id
  description       = "SSH depuis IP administrateur uniquement"
  cidr_ipv4         = var.ssh_cidr
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
}

resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.app.id
  description       = "Sortie (mises a jour, image GHCR)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_key_pair" "admin" {
  key_name   = "${var.name}-admin"
  public_key = var.ssh_public_key
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = aws_key_pair.admin.key_name

  # Au démarrage : installer Docker et lancer l'API TaskOps (port 80 -> 8000)
  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    image = var.app_image
  })
  user_data_replace_on_change = true

  # Sécurité : IMDSv2 obligatoire (protège les identifiants de l'instance)
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = { Name = "${var.name}-app" }
}
