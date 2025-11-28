locals {
  NoTraffic_irsa_enabled = var.enable_NoTraffic_irsa ? 1 : 0
}

resource "aws_iam_role" "NoTraffic_irsa" {
  count = local.NoTraffic_irsa_enabled

  name = "${var.name_prefix}-NoTraffic-irsa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:${var.NoTraffic_irsa_service_account_namespace}:${var.NoTraffic_irsa_service_account_name}"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.name_prefix}-NoTraffic-irsa"
    Environment = var.name_prefix
    Terraform   = "true"
  }
}

resource "aws_iam_role_policy" "NoTraffic_irsa_secretsmanager" {
  count = local.NoTraffic_irsa_enabled * (var.NoTraffic_irsa_secretsmanager_arn != "" ? 1 : 0)

  name = "${var.name_prefix}-NoTraffic-secrets"
  role = aws_iam_role.NoTraffic_irsa[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "SecretsManagerAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.NoTraffic_irsa_secretsmanager_arn
      }
    ], var.NoTraffic_irsa_kms_key_arn != "" ? [
      {
        Sid    = "KMSAccessForSecrets"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.NoTraffic_irsa_kms_key_arn
      }
    ] : [])
  })
}

