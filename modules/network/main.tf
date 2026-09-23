data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /16 carved into: private /19s (EKS nodes + pods, VPC CNI uses a lot of IPs),
  # public /24s (ALB + NAT only), database /24s (RDS + ElastiCache, no internet route).
  private_subnets  = [for i, _ in local.azs : cidrsubnet(var.cidr, 3, i)]
  public_subnets   = [for i, _ in local.azs : cidrsubnet(var.cidr, 8, 200 + i)]
  database_subnets = [for i, _ in local.azs : cidrsubnet(var.cidr, 8, 210 + i)]
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.7"

  name = var.name
  cidr = var.cidr
  azs  = local.azs

  private_subnets  = local.private_subnets
  public_subnets   = local.public_subnets
  database_subnets = local.database_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = var.single_nat_gateway
  one_nat_gateway_per_az = !var.single_nat_gateway

  # Database subnets get their own route table with no NAT/IGW route: fully isolated.
  create_database_subnet_group           = true
  create_database_subnet_route_table     = true
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = false

  enable_dns_hostnames = true
  enable_dns_support   = true

  # Lock down the default SG/NACL so nothing accidentally lands in a permissive group.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  enable_flow_log                                 = var.enable_flow_logs
  create_flow_log_cloudwatch_log_group            = var.enable_flow_logs
  create_flow_log_cloudwatch_iam_role             = var.enable_flow_logs
  flow_log_max_aggregation_interval               = 60
  flow_log_cloudwatch_log_group_retention_in_days = var.log_retention_days

  # Subnet discovery tags for the AWS Load Balancer Controller.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# VPC endpoints: keep AWS API traffic off the NAT gateway and the internet.
# The S3 gateway endpoint is free (and carries ECR image layers); interface
# endpoints cost ~$7/month each per AZ, so they're opt-in.
# ---------------------------------------------------------------------------
resource "aws_security_group" "endpoints" {
  count       = var.enable_interface_endpoints ? 1 : 0
  name_prefix = "${var.name}-vpce-"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.cidr]
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

module "endpoints" {
  source  = "terraform-aws-modules/vpc/aws//modules/vpc-endpoints"
  version = "~> 6.7"

  vpc_id = module.vpc.vpc_id

  endpoints = merge(
    {
      s3 = {
        service         = "s3"
        service_type    = "Gateway"
        route_table_ids = concat(module.vpc.private_route_table_ids, module.vpc.database_route_table_ids)
        tags            = { Name = "${var.name}-s3" }
      }
    },
    var.enable_interface_endpoints ? {
      for svc in ["ecr.api", "ecr.dkr", "sts", "logs", "secretsmanager"] : replace(svc, ".", "_") => {
        service             = svc
        private_dns_enabled = true
        subnet_ids          = module.vpc.private_subnets
        security_group_ids  = [aws_security_group.endpoints[0].id]
        tags                = { Name = "${var.name}-${svc}" }
      }
    } : {}
  )

  tags = var.tags
}
