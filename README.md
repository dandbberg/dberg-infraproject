# AWS EKS Keycloak + NGINX Platform

This repository provisions an end-to-end AWS environment for deploying **Keycloak** behind an **NGINX reverse proxy** on EKS. Terraform builds the network and compute foundation (VPC, EKS, RDS, IAM, ECR, KMS), while GitHub Actions automates Docker image builds and Kubernetes deployments.

---

## Highlights

- **Modular Terraform** (under `Infra/`) creates VPC, Bastion host, EKS cluster, RDS PostgreSQL, ECR, and KMS resources.
- **Keycloak + NGINX** deployment on EKS with TLS termination and Ingress exposure.
- **CI/CD** via GitHub Actions builds Docker images and deploys to EKS using GitHub OIDC to assume AWS roles.

---

## Terraform Infrastructure

| Module | Purpose | Key Outputs |
| ------ | ------- | ----------- |
| `vpc` | Dedicated VPC with 3× public + 3× private subnets, IGW, NAT gateways |
| `bastion_ec2` | Public EC2 instance for SSH/SSM access to private subnets |
| `eks` | Private EKS cluster with managed node group, IRSA support, GitHub Actions IAM role |
| `kms` | Customer-managed KMS key encrypting the RDS secret in Secrets Manager (only if RDS is enabled) |
| `rds` | PostgreSQL instance in private subnets (optional - not needed for Keycloak with embedded H2) |
| `ecr` | Repository for container images |

Remote state is stored in the S3 bucket defined in `terraform { backend "s3" … }`.

### Running Terraform (perf environment)

```bash
cd Infra
terraform init -var-file=envs/perf.auto.tfvars
terraform plan -var-file=envs/perf.auto.tfvars
terraform apply -var-file=envs/perf.auto.tfvars
```

---

## Repository Layout

```
Infra/
├── envs/                   # perf, qa, prod tfvars
├── modules/                # bastion_ec2, eks, vpc, kms, rds, ecr
├── main.tf                 # module composition
├── variables.tf            # global var definitions
├── outputs.tf              # outputs consumed by CI/CD and operators
└── provider.tf             # AWS provider + backend configuration

Deployment/
├── manifests/              # Kubernetes manifests
│   ├── keycloak.yaml
│   ├── nginx-deployment.yaml
│   ├── nginx-config.yaml
│   └── ingress.yaml
├── deploy.sh               # Deployment script
└── smoke-test.sh           # Smoke test script

.github/workflows/
├── docker-ecr.yml          # Build + push image to ECR
├── deploy-eks.yml           # Deploy to EKS cluster
└── smoke-test.yml           # Run smoke tests
```

---

## Deployment Architecture

```
┌───────────────────────────┐
│         Client            │
│   (via Ingress)           │
└───────────────┬───────────┘
                │  HTTPS (TLS)
                ▼
       ┌───────────────────┐
       │   NGINX Ingress   │
       │     Controller    │
       └─────────┬─────────┘
                 │
                 ▼
       ┌───────────────────┐
       │     NGINX         │
       │   Reverse Proxy   │
       │  (TLS terminated) │
       └─────────┬─────────┘
                 │ HTTP (internal only)
                 ▼
         ┌─────────────────┐
         │    Keycloak     │
         │    ClusterIP    │
         │  Internal Only  │
         └─────────────────┘
```

---

## CI/CD Workflow

1. **Docker build** 🛠️ (`docker-ecr.yml`)
   - Uses GitHub Actions OIDC to assume AWS IAM role
   - Builds Docker images (if custom images are needed)
   - Pushes to ECR repository

2. **Deploy to EKS** 🚀 (`deploy-eks.yml`)
   - Configures kubectl for EKS cluster
   - Deploys Keycloak and NGINX manifests
   - Verifies deployment

3. **Smoke Tests** 🧪 (`smoke-test.yml`)
   - Validates deployments are ready
   - Verifies service types (ClusterIP)
   - Tests internal connectivity

---

## Manual Deployment

### Prerequisites

- `kubectl` configured to connect to your EKS cluster
- `openssl` for TLS certificate generation

### Deploy

```bash
cd Deployment
./deploy.sh
```

The script will:
1. Generate self-signed TLS certificate
2. Create Keycloak credentials secret
3. Deploy Keycloak
4. Deploy NGINX reverse proxy
5. Deploy Ingress resource

### Custom Credentials

Set environment variables before running:

```bash
export KEYCLOAK_ADMIN=myadmin
export KEYCLOAK_ADMIN_PASSWORD=mypassword
./deploy.sh
```

### Run Smoke Tests

```bash
./smoke-test.sh
```

---

## Configuration

### Ingress Configuration

Update `Deployment/manifests/ingress.yaml` to match your domain:

```yaml
spec:
  rules:
    - host: keycloak.yourdomain.com  # Update this
      http:
        paths:
          - path: /
            pathType: Prefix
```

### NGINX Ingress Controller

Ensure NGINX Ingress Controller is installed in your EKS cluster:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/aws/deploy.yaml
```

---

## Database Configuration

**Keycloak Database Options:**

1. **Embedded H2 (Default)** - Current configuration uses `start-dev` mode with embedded H2 database
   - ✅ No RDS needed
   - ✅ Simple setup
   - ⚠️ Data is ephemeral (lost on pod restart)
   - ⚠️ Not suitable for production

2. **External PostgreSQL/MySQL (Production)** - Use RDS for persistent storage
   - Enable RDS in `Infra/envs/*.auto.tfvars` by setting `enable_rds = true`
   - Configure Keycloak to connect to RDS (requires updating Keycloak deployment with DB connection settings)
   - Provides persistent storage, backups, and high availability

**Current Setup:** RDS is **disabled by default** since Keycloak uses embedded H2. Enable RDS only if you need production-grade database persistence.

## Security Notes

- Keycloak is exposed only via NGINX (ClusterIP service)
- NGINX terminates TLS and forwards to Keycloak over HTTP internally
- Ingress exposes NGINX to external traffic
- Keycloak credentials are stored in Kubernetes secrets
- TLS certificates can be managed via cert-manager for production

---

## Cleanup

```bash
kubectl delete -f Deployment/manifests/
kubectl delete secret nginx-tls keycloak-credentials
```

---

## Differences from NoTraffic (Minikube)

This project adapts the NoTraffic deployment for EKS:

- ✅ Uses **Ingress** instead of NodePort
- ✅ Uses **ClusterIP** services (not NodePort)
- ✅ Configured for **EKS** (not minikube)
- ✅ Includes **GitHub Actions** for CI/CD
- ✅ Uses **Terraform** for infrastructure provisioning
- ❌ Removed minikube-specific configurations
- ❌ Removed VirtualBox/Docker driver dependencies

