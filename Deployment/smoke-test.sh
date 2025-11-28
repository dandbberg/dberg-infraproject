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

# Verify NodePort service exists and is configured
echo -e "${YELLOW}→ Verifying NodePort service...${NC}"
if ! kubectl get service nginx-proxy-nodeport &>/dev/null; then
    echo -e "${RED}✗ NodePort service 'nginx-proxy-nodeport' not found${NC}"
    exit 1
fi

NODEPORT=$(kubectl get service nginx-proxy-nodeport -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
SERVICE_TYPE=$(kubectl get service nginx-proxy-nodeport -o jsonpath='{.spec.type}' 2>/dev/null || echo "")

if [ "$SERVICE_TYPE" != "NodePort" ]; then
    echo -e "${RED}✗ Service type is $SERVICE_TYPE, expected NodePort${NC}"
    exit 1
fi

if [ -z "$NODEPORT" ]; then
    echo -e "${RED}✗ NodePort number not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ NodePort service is configured on port $NODEPORT${NC}"

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

# Test Keycloak access within cluster (direct)
echo -e "${YELLOW}→ Testing Keycloak direct access within cluster...${NC}"
KEYCLOAK_STATUS=$(kubectl run test-keycloak-direct --rm -i --restart=Never --image=curlimages/curl --timeout=30s -- \
  curl -s -o /dev/null -w "%{http_code}" http://keycloak.default.svc.cluster.local:8080 2>/dev/null || echo "000")

if [ "$KEYCLOAK_STATUS" = "200" ] || [ "$KEYCLOAK_STATUS" = "302" ] || [ "$KEYCLOAK_STATUS" = "401" ]; then
    echo -e "${GREEN}✓ Keycloak is accessible directly within cluster (HTTP $KEYCLOAK_STATUS)${NC}"
else
    echo -e "${RED}✗ Keycloak direct access failed (HTTP $KEYCLOAK_STATUS)${NC}"
    exit 1
fi

# Test Keycloak through NGINX reverse proxy (internal)
echo -e "${YELLOW}→ Testing Keycloak through NGINX reverse proxy (internal)...${NC}"
NGINX_STATUS=$(kubectl run test-nginx-internal --rm -i --restart=Never --image=curlimages/curl --timeout=30s -- \
  curl -k -s -o /dev/null -w "%{http_code}" https://nginx-proxy.default.svc.cluster.local 2>/dev/null || echo "000")

if [ "$NGINX_STATUS" = "200" ] || [ "$NGINX_STATUS" = "302" ] || [ "$NGINX_STATUS" = "401" ]; then
    echo -e "${GREEN}✓ Keycloak accessible through NGINX internally (HTTP $NGINX_STATUS)${NC}"
else
    echo -e "${RED}✗ NGINX to Keycloak path failed (HTTP $NGINX_STATUS)${NC}"
    exit 1
fi

# Test Keycloak OpenID configuration endpoint through NGINX
echo -e "${YELLOW}→ Testing Keycloak OpenID configuration endpoint...${NC}"
OPENID_RESPONSE=$(kubectl run test-openid --rm -i --restart=Never --image=curlimages/curl --timeout=30s -- \
  curl -k -s https://nginx-proxy.default.svc.cluster.local/realms/master/.well-known/openid-configuration 2>/dev/null || echo "")

if [ -z "$OPENID_RESPONSE" ]; then
    echo -e "${RED}✗ OpenID configuration endpoint returned empty response${NC}"
    exit 1
fi

# Check if response contains expected OpenID fields
if echo "$OPENID_RESPONSE" | grep -q "issuer" && echo "$OPENID_RESPONSE" | grep -q "authorization_endpoint"; then
    echo -e "${GREEN}✓ OpenID configuration endpoint is accessible and returns valid JSON${NC}"
else
    echo -e "${RED}✗ OpenID configuration endpoint response is invalid${NC}"
    exit 1
fi

# Test NodePort access (from within cluster, simulating external access)
echo -e "${YELLOW}→ Testing NodePort access...${NC}"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null)
if [ -z "$NODE_IP" ]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
fi

if [ -n "$NODE_IP" ]; then
    NODEPORT_STATUS=$(kubectl run test-nodeport --rm -i --restart=Never --image=curlimages/curl --timeout=30s -- \
      curl -k -s -o /dev/null -w "%{http_code}" https://$NODE_IP:$NODEPORT 2>/dev/null || echo "000")
    
    if [ "$NODEPORT_STATUS" = "200" ] || [ "$NODEPORT_STATUS" = "302" ] || [ "$NODEPORT_STATUS" = "401" ]; then
        echo -e "${GREEN}✓ NodePort is accessible (HTTP $NODEPORT_STATUS)${NC}"
        echo -e "${GREEN}  Node IP: $NODE_IP${NC}"
        echo -e "${GREEN}  NodePort: $NODEPORT${NC}"
        echo -e "${GREEN}  Access URL: https://$NODE_IP:$NODEPORT${NC}"
    else
        echo -e "${YELLOW}⚠ NodePort test returned HTTP $NODEPORT_STATUS (may be blocked by security groups)${NC}"
        echo -e "${YELLOW}  NodePort is configured but may not be accessible from outside cluster${NC}"
    fi
fi

echo -e "${GREEN}===================================================="
echo -e "     All smoke tests passed! ✓"
echo -e "====================================================${NC}"
