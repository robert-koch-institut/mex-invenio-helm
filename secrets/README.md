# MEX Invenio Secrets

This directory contains templates and scripts for managing Kubernetes secrets for the MEX Invenio deployment.

## Required Secret Keys

The following secrets are required for the MEX Invenio deployment:

### Invenio Application Secrets
- `INVENIO_SECRET_KEY`: Flask secret key (UUID format) - used for session signing and general cryptographic operations
- `INVENIO_SECURITY_LOGIN_SALT`: Security login salt (UUID format) - used for password hashing
- `INVENIO_CSRF_SECRET_SALT`: CSRF protection salt (UUID format) - used for CSRF token generation

### Database & Message Broker Secrets  
- `rabbitmq-password`: RabbitMQ authentication password (random string, 27 characters recommended)
- `postgresql-hostname`: External PostgreSQL server hostname
- `postgresql-username`: External PostgreSQL username
- `postgresql-password`: External PostgreSQL database password
- `postgresql-database`: External PostgreSQL database name

### MEX Import Configuration
- `MEX_IMPORT_ENDPOINT_URL`: S3-compatible endpoint URL for MEX data imports
- `MEX_IMPORT_AWS_KEY_ID`: AWS access key ID for S3 bucket access
- `MEX_IMPORT_AWS_SECRET`: AWS secret access key for S3 bucket access
- `MEX_IMPORT_BUCKET`: S3 bucket name containing MEX import data
- `MEX_IMPORT_EMAIL`: Email address for import notifications and error reporting

## Creating the Secret

### Method 1: Using the Script (Recommended)

Run the deployment script to generate and create the secret:

```bash
./scripts/create-secrets.sh
```

This will:
1. Generate a YAML file with the secret structure
2. Show you the generated secret (without exposing values)
3. Prompt you to apply it

If the apply step fails (e.g., cluster not configured), you can apply the generated file manually later:

```bash
kubectl apply -f secrets/mex-invenio-secrets-generated.yaml
```

### Method 2: Manual Creation

If you prefer to create the secret manually:

```bash
kubectl create secret generic mex-invenio-secrets -n mex \
  --from-literal=INVENIO_SECRET_KEY="$(uuidgen)" \
  --from-literal=INVENIO_SECURITY_LOGIN_SALT="$(uuidgen)" \
  --from-literal=INVENIO_CSRF_SECRET_SALT="$(uuidgen)" \
  --from-literal=rabbitmq-password="$(pwgen -N 1 27)" \
  --from-literal=postgresql-hostname="your-postgres-host" \
  --from-literal=postgresql-username="your-postgres-user" \
  --from-literal=postgresql-password="your-postgres-password" \
  --from-literal=postgresql-database="your-postgres-database" \
  --from-literal=MEX_IMPORT_ENDPOINT_URL="your-s3-endpoint" \
  --from-literal=MEX_IMPORT_AWS_KEY_ID="your-aws-key-id" \
  --from-literal=MEX_IMPORT_AWS_SECRET="your-aws-secret" \
  --from-literal=MEX_IMPORT_BUCKET="your-import-bucket" \
  --from-literal=MEX_IMPORT_EMAIL="your-import-email"
```

## Using the Secret

Once created, reference the secret in your Helm values:

```yaml
invenio:
  existingSecret: "mex-invenio-secrets"
  # extraConfig values will be pulled from the secret automatically

rabbitmq:
  auth:
    existingSecret: "mex-invenio-secrets"
    existingSecretPasswordKey: "rabbitmq-password"

# Option 1: Use containerized PostgreSQL
postgresql:
  enabled: true
  auth:
    existingSecret: "mex-invenio-secrets"
    existingSecretPasswordKey: "postgresql-password"

# Option 2: Use external PostgreSQL (toggle - only use one)
# postgresql:
#   enabled: false
# postgresqlExternal:
#   existingSecret: "mex-invenio-secrets"
#   existingSecretHostnameKey: "postgresql-hostname"
#   existingSecretUsernameKey: "postgresql-username"
#   existingSecretPasswordKey: "postgresql-password"
#   existingSecretDatabaseKey: "postgresql-database"
```

## Verifying the Secret

Check that the secret was created successfully:

```bash
# Verify secret exists
kubectl get secret mex-invenio-secrets -n mex

# Show secret structure (without values)
kubectl describe secret mex-invenio-secrets -n mex

# Test access from a pod
kubectl -n mex exec -it <web-pod> -- env | grep INVENIO_SECRET_KEY
```

## Important Notes

- ⚠️ **Never commit actual secret values to git**
- ⚠️ **The generated YAML files in this directory should be gitignored**
- ✅ **Always regenerate secrets for new environments**
- ✅ **Use the same secrets across helm upgrades to maintain data access**
- ✅ **Store production secrets securely (e.g., in a password manager)**

## Troubleshooting

### Script Failed to Apply Secret

If the script fails during the apply step (e.g., cluster not configured):

```bash
# Apply the generated file manually after configuring cluster access
kubectl apply -f secrets/mex-invenio-secrets-generated.yaml
```

### Updating Existing Secrets

If you need to update secrets:

```bash
# Delete existing secret
kubectl delete secret mex-invenio-secrets -n mex

# Recreate with new values
./scripts/create-secrets.sh

# Restart deployments to pick up new secrets
kubectl rollout restart deployment/mex-invenio-web -n mex
kubectl rollout restart deployment/mex-invenio-worker -n mex
```