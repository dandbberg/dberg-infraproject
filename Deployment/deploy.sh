#!/bin/bash
set -e

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
NC="\033[0m"

echo -e "${BLUE}===================================================="
echo -e "     Keycloak + NGINX Reverse Proxy Deployment"
echo -e "     EKS Cluster Deployment"
echo -e "====================================================${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    echo -e "${YELLOW}Please configure kubectl to connect to your EKS cluster${NC}"
    exit 1
fi

### ---------------------------------------------------
### 1. Generate TLS Certificate
### ---------------------------------------------------
echo -e "${YELLOW}→ Generating self-signed TLS certificate...${NC}"

openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=keycloak.example.com" >/dev/null 2>&1

kubectl delete secret nginx-tls --ignore-not-found >/dev/null 2>&1
kubectl create secret tls nginx-tls --key tls.key --cert tls.crt >/dev/null

echo -e "${GREEN}✓ TLS certificate stored as secret 'nginx-tls'.${NC}"

### ---------------------------------------------------
### 2. Create Keycloak Credentials Secret
### ---------------------------------------------------
echo -e "${YELLOW}→ Creating Keycloak credentials secret...${NC}"

# Use environment variables or generate secure defaults
KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN:-admin}"

if [[ -z "${KEYCLOAK_ADMIN_PASSWORD}" ]]; then
  # Generate a random secure password if not provided
  KEYCLOAK_ADMIN_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
  echo -e "${YELLOW}  Generated secure password (saved to .keycloak-credentials)${NC}"
  echo "KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN_USER}" > .keycloak-credentials
  echo "KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD}" >> .keycloak-credentials
  chmod 600 .keycloak-credentials
  echo -e "${GREEN}  Username: ${KEYCLOAK_ADMIN_USER}${NC}"
  echo -e "${GREEN}  Password: ${KEYCLOAK_ADMIN_PASSWORD}${NC}"
else
  echo -e "${GREEN}  Using provided credentials${NC}"
fi

kubectl delete secret keycloak-credentials --ignore-not-found >/dev/null 2>&1
kubectl create secret generic keycloak-credentials \
  --from-literal=admin-username="${KEYCLOAK_ADMIN_USER}" \
  --from-literal=admin-password="${KEYCLOAK_ADMIN_PASSWORD}" >/dev/null

echo -e "${GREEN}✓ Keycloak credentials stored as secret 'keycloak-credentials'.${NC}"

### ---------------------------------------------------
### 3. Deploy Keycloak (ClusterIP, official image)
### ---------------------------------------------------
echo -e "${YELLOW}→ Deploying Keycloak (official Quay.io image)...${NC}"

kubectl apply -f manifests/keycloak.yaml >/dev/null

echo -e "${YELLOW}→ Waiting for Keycloak to become ready...${NC}"
kubectl rollout status deployment/keycloak --timeout=300s

echo -e "${GREEN}✓ Keycloak deployed & running.${NC}"

### ---------------------------------------------------
### 4. Deploy NGINX Reverse Proxy
### ---------------------------------------------------
echo -e "${YELLOW}→ Deploying NGINX reverse proxy...${NC}"

kubectl apply -f manifests/nginx-config.yaml >/dev/null
kubectl apply -f manifests/nginx-deployment.yaml >/dev/null

echo -e "${YELLOW}→ Waiting for NGINX to become ready...${NC}"
kubectl rollout status deployment/nginx-proxy --timeout=300s

echo -e "${GREEN}✓ NGINX reverse proxy deployed.${NC}"

### ---------------------------------------------------
### 5. Deploy Ingress
### ---------------------------------------------------
echo -e "${YELLOW}→ Deploying Ingress resource...${NC}"

kubectl apply -f manifests/ingress.yaml >/dev/null

echo -e "${GREEN}✓ Ingress deployed.${NC}"

### ---------------------------------------------------
### 6. Cleanup temporary files
### ---------------------------------------------------
rm -f tls.key tls.crt

echo -e "${GREEN}===================================================="
echo -e "     🎉 Deployment Completed Successfully!"
echo -e "====================================================${NC}"
echo -e "${YELLOW}Note: Update the Ingress hostname in manifests/ingress.yaml${NC}"
echo -e "${YELLOW}      to match your domain and ensure NGINX Ingress Controller${NC}"
echo -e "${YELLOW}      is installed in your EKS cluster.${NC}"

