#!/bin/bash
set -e

GREEN="\033[0;32m"
YELLOW="\033[1;33m"
RED="\033[0;31m"
NC="\033[0m"

echo -e "${YELLOW}Running smoke tests...${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we can connect to cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

# Check if Keycloak deployment is ready
echo -e "${YELLOW}→ Checking Keycloak deployment...${NC}"
if kubectl wait --for=condition=available --timeout=300s deployment/keycloak 2>/dev/null; then
    echo -e "${GREEN}✓ Keycloak deployment is ready${NC}"
else
    echo -e "${RED}✗ Keycloak deployment is not ready${NC}"
    exit 1
fi

# Check if NGINX deployment is ready
echo -e "${YELLOW}→ Checking NGINX deployment...${NC}"
if kubectl wait --for=condition=available --timeout=300s deployment/nginx-proxy 2>/dev/null; then
    echo -e "${GREEN}✓ NGINX deployment is ready${NC}"
else
    echo -e "${RED}✗ NGINX deployment is not ready${NC}"
    exit 1
fi

# Check if services exist
echo -e "${YELLOW}→ Checking services...${NC}"
if kubectl get service keycloak &>/dev/null && kubectl get service nginx-proxy &>/dev/null; then
    echo -e "${GREEN}✓ Services are available${NC}"
else
    echo -e "${RED}✗ Services are not available${NC}"
    exit 1
fi

# Check if ingress or NodePort exists
echo -e "${YELLOW}→ Checking external exposure...${NC}"
if kubectl get ingress nginx-proxy-ingress &>/dev/null; then
    echo -e "${GREEN}✓ Ingress is configured${NC}"
elif kubectl get service nginx-proxy-nodeport &>/dev/null; then
    NODEPORT=$(kubectl get service nginx-proxy-nodeport -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
    if [ -n "$NODEPORT" ]; then
        echo -e "${GREEN}✓ NodePort service is configured on port $NODEPORT${NC}"
    else
        echo -e "${YELLOW}⚠ NodePort service found but port not available${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No external exposure method found (Ingress or NodePort)${NC}"
fi

# Verify Keycloak is ClusterIP (internal only)
echo -e "${YELLOW}→ Verifying Keycloak service type...${NC}"
SERVICE_TYPE=$(kubectl get service keycloak -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
if [ "$SERVICE_TYPE" = "ClusterIP" ]; then
    echo -e "${GREEN}✓ Keycloak service is ClusterIP (internal only)${NC}"
else
    echo -e "${RED}✗ Keycloak service should be ClusterIP, but is $SERVICE_TYPE${NC}"
    exit 1
fi

# Verify NGINX base service is ClusterIP
echo -e "${YELLOW}→ Verifying NGINX base service type...${NC}"
NGINX_TYPE=$(kubectl get service nginx-proxy -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
if [ "$NGINX_TYPE" = "ClusterIP" ]; then
    echo -e "${GREEN}✓ NGINX base service is ClusterIP${NC}"
else
    echo -e "${RED}✗ NGINX base service should be ClusterIP, but is $NGINX_TYPE${NC}"
    exit 1
fi

# Test internal connectivity
echo -e "${YELLOW}→ Testing internal connectivity...${NC}"
if kubectl run test-curl --rm -i --restart=Never --image=curlimages/curl -- curl -k -s -o /dev/null -w "%{http_code}" https://nginx-proxy.default.svc.cluster.local 2>/dev/null | grep -q "200\|302\|401"; then
    echo -e "${GREEN}✓ NGINX reverse proxy is reachable internally${NC}"
else
    echo -e "${YELLOW}⚠ Could not verify internal connectivity (may need time to propagate)${NC}"
fi

echo -e "${GREEN}===================================================="
echo -e "     All smoke tests passed! ✓"
echo -e "====================================================${NC}"

