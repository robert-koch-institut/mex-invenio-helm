#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

NAMESPACE="mex"
SECRET_NAME="mex-invenio-secrets"
OUTPUT_FILE="secrets/${SECRET_NAME}-generated.yaml"

echo -e "${GREEN}Creating MEX Invenio secrets...${NC}"
echo

# Check if required tools are available
if ! command -v uuidgen &> /dev/null; then
    echo -e "${RED}Error: uuidgen command not found. Please install uuid-runtime package.${NC}"
    exit 1
fi

if ! command -v pwgen &> /dev/null; then
    echo -e "${RED}Error: pwgen command not found. Please install pwgen package.${NC}"
    exit 1
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl command not found. Please install kubectl.${NC}"
    exit 1
fi

# Check if secret already exists
if kubectl get secret $SECRET_NAME -n $NAMESPACE &> /dev/null; then
    echo -e "${YELLOW}Warning: Secret '$SECRET_NAME' already exists in namespace '$NAMESPACE'${NC}"
    read -p "Do you want to recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Deleting existing secret..."
        kubectl delete secret $SECRET_NAME -n $NAMESPACE
    else
        echo "Aborted."
        exit 0
    fi
fi

# Generate the secret values
echo "Generating secret values..."
INVENIO_SECRET_KEY=$(uuidgen)
INVENIO_SECURITY_LOGIN_SALT=$(uuidgen)
INVENIO_CSRF_SECRET_SALT=$(uuidgen)
RABBITMQ_PASSWORD=$(pwgen -N 1 27)

# Prompt for PostgreSQL configuration
echo
echo -e "${YELLOW}PostgreSQL Configuration:${NC}"
read -p "Use external PostgreSQL? (y/N): " -n 1 -r USE_EXTERNAL_POSTGRES
echo
if [[ $USE_EXTERNAL_POSTGRES =~ ^[Yy]$ ]]; then
    read -p "PostgreSQL hostname: " POSTGRESQL_HOSTNAME
    read -p "PostgreSQL username: " POSTGRESQL_USERNAME
    read -s -p "PostgreSQL password: " POSTGRESQL_PASSWORD
    echo
    read -p "PostgreSQL database name: " POSTGRESQL_DATABASE
    USE_EXTERNAL=true
else
    POSTGRESQL_PASSWORD=$(pwgen -N 1 17)
    USE_EXTERNAL=false
fi

# Prompt for MEX Import configuration
echo
echo -e "${YELLOW}MEX Import Configuration:${NC}"
read -p "S3 Endpoint URL: " MEX_IMPORT_ENDPOINT_URL
read -p "AWS Access Key ID: " MEX_IMPORT_AWS_KEY_ID
read -s -p "AWS Secret Access Key: " MEX_IMPORT_AWS_SECRET
echo
read -p "S3 Bucket name: " MEX_IMPORT_BUCKET
read -p "Import account email: " MEX_IMPORT_EMAIL

# Create the secret and save to file
echo "Creating secret manifest..."
mkdir -p secrets

# Build kubectl command with core secrets
KUBECTL_CMD="kubectl create secret generic $SECRET_NAME -n $NAMESPACE \
  --from-literal=INVENIO_SECRET_KEY=\"$INVENIO_SECRET_KEY\" \
  --from-literal=INVENIO_SECURITY_LOGIN_SALT=\"$INVENIO_SECURITY_LOGIN_SALT\" \
  --from-literal=INVENIO_CSRF_SECRET_SALT=\"$INVENIO_CSRF_SECRET_SALT\" \
  --from-literal=rabbitmq.auth.password=\"$RABBITMQ_PASSWORD\" \
  --from-literal=MEX_IMPORT_ENDPOINT_URL=\"$MEX_IMPORT_ENDPOINT_URL\" \
  --from-literal=MEX_IMPORT_AWS_KEY_ID=\"$MEX_IMPORT_AWS_KEY_ID\" \
  --from-literal=MEX_IMPORT_AWS_SECRET=\"$MEX_IMPORT_AWS_SECRET\" \
  --from-literal=MEX_IMPORT_BUCKET=\"$MEX_IMPORT_BUCKET\" \
  --from-literal=MEX_IMPORT_EMAIL=\"$MEX_IMPORT_EMAIL\""

# Add PostgreSQL secrets based on configuration choice
if [[ $USE_EXTERNAL == true ]]; then
    KUBECTL_CMD="$KUBECTL_CMD \
  --from-literal=postgresqlExternal.hostname=\"$POSTGRESQL_HOSTNAME\" \
  --from-literal=postgresqlExternal.username=\"$POSTGRESQL_USERNAME\" \
  --from-literal=postgresqlExternal.password=\"$POSTGRESQL_PASSWORD\" \
  --from-literal=postgresqlExternal.databaseName=\"$POSTGRESQL_DATABASE\""
else
    KUBECTL_CMD="$KUBECTL_CMD \
  --from-literal=postgresql.auth.password=\"$POSTGRESQL_PASSWORD\""
fi

# Execute the command
eval "$KUBECTL_CMD --dry-run=client -o yaml > $OUTPUT_FILE"

echo -e "${GREEN}✓ Secret manifest generated at: $OUTPUT_FILE${NC}"
echo

# Show the structure (without values)
echo "Secret structure:"
echo "├── INVENIO_SECRET_KEY: $(echo $INVENIO_SECRET_KEY | sed 's/./*/g')"
echo "├── INVENIO_SECURITY_LOGIN_SALT: $(echo $INVENIO_SECURITY_LOGIN_SALT | sed 's/./*/g')"
echo "├── INVENIO_CSRF_SECRET_SALT: $(echo $INVENIO_CSRF_SECRET_SALT | sed 's/./*/g')"
echo "├── rabbitmq.auth.password: $(echo $RABBITMQ_PASSWORD | sed 's/./*/g')"
if [[ $USE_EXTERNAL == true ]]; then
    echo "├── postgresqlExternal.hostname: $(echo $POSTGRESQL_HOSTNAME | sed 's/./*/g')"
    echo "├── postgresqlExternal.username: $(echo $POSTGRESQL_USERNAME | sed 's/./*/g')"
    echo "├── postgresqlExternal.password: $(echo $POSTGRESQL_PASSWORD | sed 's/./*/g')"
    echo "├── postgresqlExternal.databaseName: $(echo $POSTGRESQL_DATABASE | sed 's/./*/g')"
else
    echo "├── postgresql.auth.password: $(echo $POSTGRESQL_PASSWORD | sed 's/./*/g')"
fi
echo "├── MEX_IMPORT_ENDPOINT_URL: $(echo $MEX_IMPORT_ENDPOINT_URL | sed 's/./*/g')"
echo "├── MEX_IMPORT_AWS_KEY_ID: $(echo $MEX_IMPORT_AWS_KEY_ID | sed 's/./*/g')"
echo "├── MEX_IMPORT_AWS_SECRET: $(echo $MEX_IMPORT_AWS_SECRET | sed 's/./*/g')"
echo "├── MEX_IMPORT_BUCKET: $(echo $MEX_IMPORT_BUCKET | sed 's/./*/g')"
echo "└── MEX_IMPORT_EMAIL: $(echo $MEX_IMPORT_EMAIL | sed 's/./*/g')"
echo

# Ask if user wants to apply the secret
read -p "Apply the secret to the cluster now? (Y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Secret manifest created but not applied.${NC}"
    echo "To apply later, run: kubectl apply -f $OUTPUT_FILE"
else
    echo "Applying secret to cluster..."
    kubectl apply -f $OUTPUT_FILE
    
    # Verify the secret was created
    if kubectl get secret $SECRET_NAME -n $NAMESPACE &> /dev/null; then
        echo -e "${GREEN}✓ Secret successfully created in cluster${NC}"
        echo
        echo "Secret details:"
        kubectl describe secret $SECRET_NAME -n $NAMESPACE
    else
        echo -e "${RED}✗ Failed to create secret in cluster${NC}"
        exit 1
    fi
fi

echo
echo -e "${GREEN}Next steps:${NC}"
echo "1. Update your values-overrides-mexhost.yaml to use existingSecret: '$SECRET_NAME'"
echo "2. Remove secret_key, security_login_salt, csrf_secret_salt from your values"
echo "3. Deploy with: helm upgrade -f values-overrides-mexhost.yaml -n $NAMESPACE mex-invenio ."
echo
echo -e "${YELLOW}Important: Add '$OUTPUT_FILE' to your .gitignore to avoid committing secrets!${NC}"