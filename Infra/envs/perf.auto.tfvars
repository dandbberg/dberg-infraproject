aws_region  = "eu-west-1"
name_prefix = "dberg-perf"
vpc_cidr    = "10.20.0.0/16"
azs         = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
ami_id          = "ami-04fc3aeb3378acab2"
allowed_ssh_cidr = "87.68.225.147/32"
instance_type   = "t3.micro"
key_pair_name   = "dberg"
cluster_name         = "eks"
cluster_version      = "1.33"
map_user_userarn     = "arn:aws:iam::919649607464:user/dberg"
map_user_username    = "dberg"
map_user_groups      = ["system:masters"]
desired_size         = 1
max_size             = 2
min_size             = 1
eks_instance_type    = "t3.medium"
node_name            = "node"
bastion_sg_eks_rule_port = 443

# RDS Configuration (optional - not needed for Keycloak with embedded H2 database)
# Enable RDS only if you want to use external PostgreSQL/MySQL for Keycloak production deployment
enable_rds                      = false
rds_db_identifier               = "app-db"
rds_engine                      = "postgres"
rds_engine_version              = "17.4"
rds_instance_class              = "db.t3.micro"
rds_allocated_storage           = 20
rds_db_name                     = "keycloak"
rds_db_username                 = "keycloakadmin"
rds_manage_master_user_password = true  # RDS will manage password in Secrets Manager (secure, no password in git)
rds_backup_retention_period     = 7
rds_skip_final_snapshot         = true  # Set to false in production
rds_deletion_protection         = false  # Set to true in production
#
# KMS Configuration (only needed if RDS is enabled)
kms_deletion_window_in_days     = 30
kms_enable_key_rotation         = true
#
# GitHub Actions Configuration (for CI/CD)
# IMPORTANT: Update the repository subjects below to match your actual GitHub repository
# Format: "repo:OWNER/REPO:ref:refs/heads/BRANCH" or "repo:OWNER/REPO:pull_request"
enable_github_actions            = true
github_repository_subjects       = [
  "repo:dandbberg/dberg-infraproject:ref:refs/heads/main",
  "repo:dandbberg/dberg-infraproject:pull_request"
]
github_actions_kubernetes_groups = ["system:masters"]

# IRSA / Secrets
enable_NoTraffic_irsa                   = true
NoTraffic_irsa_service_account_name     = "notraffic-notraffic-chart"
NoTraffic_irsa_service_account_namespace = "default"
#During new deploy the below ARN's need to be replaced
#NoTraffic_irsa_secretsmanager_arn      = "arn:aws:secretsmanager:eu-west-1:919649607464:secret:rds!db-26c7501a-dfda-4f82-9c37-0f18181ecb92-jgvCkQ"
NoTraffic_irsa_kms_key_arn             = "arn:aws:kms:eu-west-1:919649607464:key/1f74d465-77d2-45fd-9561-9c6d9ccb08db"

#
# ECR Configuration (Docker image repositories)
enable_ecr                       = false
ecr_repository_names             = ["notraffic-ecr"]
ecr_scan_on_push                 = true
