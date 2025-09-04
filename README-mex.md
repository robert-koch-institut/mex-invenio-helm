# [Beta] Invenio Helm chart: RKI / mex instructions

**Currently for DEV / CI - using pre-signed certificates on nginx ingress**

The deployment takes about 2-3 minutes. We've added an init container to the install-init
job in order to wait for OpenSearch to become available. This in turn has required an
increase in the initial delay of the startup probes for the worker and worker-beat pods.

# Setup

Tools required are `helm`, and [Kubectl](https://go.microsoft.com/fwlink/?linkid=2233742).

## Connect to the cluster

TODO: Plusserver docs

## Install CertManager on the cluster

CertManager is used to automatically handle SSL certificates outwith the service itself. It also gives us a simple way
to verify for LetsEncrypt certs. We've had some trouble with this on Plusserver.

The necessary steps on a fresh cluster are:

## Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io --force-update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --set crds.enabled=true
```

This installation occurs on the same cluster but in a different namespace to the InvenioRDM application.

### [Teardown Cert-Manager](https://cert-manager.io/v1.2-docs/installation/uninstall/kubernetes/)

```shell
helm --namespace cert-manager delete cert-manager
kubectl delete namespace cert-manager
```

# Push the container image to the repository

We're using the Github container repository, so we build and push the containers:

In the instance repo:

```bash
docker build -t ghcr.io/robert-koch-institut/mex-invenio .
docker push ghcr.io/robert-koch-institut/mex-invenio
```

# InvenioRDM Deployment commands

To install, cd into `charts/invenio`, first run

```bash
helm dependency build
```

To get the charts for `opensearch`, `postgresql`, `rabbitmq`, and `redis`.

Note that you can add the argument `--debug` to all `helm` commands for a bit more verbosity.

If the namespace invenio doesn't exist you need to add the argument `--create-namespace`.
You can do a dry run of a `helm` command by adding, `--dry-run`.

Some of the secret values in `values-overrides-mex.yaml` have been obscured with the text `REPLACE-ME` and not
checked into the repo.
These need to be supplied at runtime (so that they can be templated via GitHub Secrets for CI). Unfortunately this makes
the following commands rather lengthy. Feel free to use environment variables to ease the process (see below).

```bash
helm install -f values-overrides-mex.yaml -n mex mex-invenio . [--create-namespace] \
  --set invenio.secret_key=<your_key> \
  --set invenio.security_login_salt=<your_login_salt> \
  --set invenio.csrf_secret_salt=<another_secret_salt> \
  --set rabbitmq.auth.password=<your_mq_password> \
  --set postgresql.auth.password=<your_pg_password>
```

`mex-invenio` is the deployment name in `helm`, which you'll use for subsequent management commands.

If you want to apply a change of configuration you can upgrade like so:

```bash
helm upgrade -f values-overrides-mex.yaml -n mex mex-invenio . \
  --set invenio.secret_key=<your_key> \
  --set invenio.security_login_salt=<your_login_salt> \
  --set invenio.csrf_secret_salt=<another_secret_salt> \
  --set rabbitmq.auth.password=<your_mq_password> \
  --set postgresql.auth.password=<your_pg_password>
```

You **MUST** provide the same secrets as before if you wish for the existing data in the instance to be accessible.

## Secret Management

The project uses Kubernetes secrets for secure credential storage:

### 1. Create secrets
Run the interactive script to generate and apply secrets:
```bash
scripts/create-secrets.sh
```

### 2. Deploy with secrets
Extract secret values and use `--set` flags:

#### For containerised PostgreSQL deployment:
```bash
# Extract password values from secret
POSTGRESQL_PASSWORD=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresql\.auth\.password}' | base64 -d)
RABBITMQ_PASSWORD=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.rabbitmq\.auth\.password}' | base64 -d)

# Deploy with extracted secret values
helm install -f values-overrides-mexhost.yaml -n mex mex-invenio . \
  --set postgresql.auth.password="$POSTGRESQL_PASSWORD" \
  --set postgresql.auth.username="invenio" \
  --set postgresql.auth.database="invenio" \
  --set rabbitmq.auth.password="$RABBITMQ_PASSWORD"
```

#### For external PostgreSQL deployment:
```bash
# Extract secret values for external PostgreSQL
POSTGRESQL_HOSTNAME=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresqlExternal\.hostname}' | base64 -d)
RABBITMQ_PASSWORD=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.rabbitmq\.auth\.password}' | base64 -d)
POSTGRESQL_DATABASE=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresqlExternal\.databaseName}' | base64 -d)
POSTGRESQL_PASSWORD=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresqlExternal\.password}' | base64 -d)
POSTGRESQL_USERNAME=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresqlExternal\.username}' | base64 -d)

# Deploy with extracted secret values
helm install -f values-overrides-mexhost.yaml -n mex mex-invenio . \
  --set postgresqlExternal.hostname="$POSTGRESQL_HOSTNAME" \
  --set rabbitmq.auth.password="$RABBITMQ_PASSWORD" \
  --set postgresqlExternal.databaseName="$POSTGRESQL_DATABASE" \
  --set postgresqlExternal.password="$POSTGRESQL_PASSWORD" \
  --set postgresqlExternal.username="$POSTGRESQL_USERNAME"
```

### 3. Available secret keys
- `postgresql.auth.password`: PostgreSQL database password
- `rabbitmq.auth.password`: RabbitMQ message queue password  
- `INVENIO_SECRET_KEY`: Application secret key
- `INVENIO_CSRF_SECRET_SALT`: CSRF protection salt
- `INVENIO_SECURITY_LOGIN_SALT`: Login security salt
- `MEX_IMPORT_*`: S3 import configuration (endpoint, credentials, bucket, etc.)

### 4. Upgrade commands

Changes such as replacing the image hash (for a code update) will trigger a rolling-restart of the web and worker pods.
New ones will appear with a new hash name, and the old ones will terminate in turn. This only works if the charts use full image hashes; `:latest`
doesn't constitute a change to the charts so won't recognise the update and perform the rolling restart.

#### For containerised PostgreSQL deployment:
```bash
# Extract passwords
POSTGRESQL_PASSWORD=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresql\.auth\.password}' | base64 -d)
RABBITMQ_PASSWORD=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.rabbitmq\.auth\.password}' | base64 -d)

# Upgrade deployment
helm upgrade -f values-overrides-mexhost.yaml -n mex mex-invenio . \
  --set postgresql.auth.password="$POSTGRESQL_PASSWORD" \
  --set postgresql.auth.username="invenio" \
  --set postgresql.auth.database="invenio" \
  --set rabbitmq.auth.password="$RABBITMQ_PASSWORD"
```

#### For external PostgreSQL deployment:
```bash
# Extract secret values for external PostgreSQL
POSTGRESQL_HOSTNAME=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresqlExternal\.hostname}' | base64 -d)
RABBITMQ_PASSWORD=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.rabbitmq\.auth\.password}' | base64 -d)
POSTGRESQL_DATABASE=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresqlExternal\.databaseName}' | base64 -d)
POSTGRESQL_PASSWORD=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresqlExternal\.password}' | base64 -d)
POSTGRESQL_USERNAME=$(kubectl get secret mex-invenio-secrets -n mex -o jsonpath='{.data.postgresqlExternal\.username}' | base64 -d)

# Upgrade deployment
helm upgrade -f values-overrides-mexhost.yaml -n mex mex-invenio . \
  --set postgresqlExternal.hostname="$POSTGRESQL_HOSTNAME" \
  --set rabbitmq.auth.password="$RABBITMQ_PASSWORD" \
  --set postgresqlExternal.databaseName="$POSTGRESQL_DATABASE" \
  --set postgresqlExternal.password="$POSTGRESQL_PASSWORD" \
  --set postgresqlExternal.username="$POSTGRESQL_USERNAME"
```

## Checking on installation progress

Remember to check pods in the expected namespace (below shows a rolling restart in-progress, see the image change)

```bash
kubectl get pods --namespace mex

NAME                                       READY   STATUS        RESTARTS         AGE
...
mex-invenio-web-65795577d7-2h26l           2/2     Running             0          4h18m
mex-invenio-web-65795577d7-4ps6c           2/2     Running             0          4h18m
mex-invenio-web-65795577d7-5wlgg           2/2     Running             0          4h18m
mex-invenio-web-65795577d7-855p9           2/2     Running             0          4h14m
mex-invenio-web-78b7656dc9-4tfb8           0/2     Init:0/1            0          29s
mex-invenio-web-78b7656dc9-lkz67           0/2     Init:0/1            0          29s
mex-invenio-web-78b7656dc9-wbtb2           0/2     Init:0/1            0          29s
...
```

Check the `STATUS` and `READY` columns - if they are stuck in a `Pending` state your cluster may not have enough
resources.
To track the installation in real-time, it's helpful to use the `watch` command:

```bash
$ watch -n 10 kubectl get pods -n mex

Every 10.0s: kubectl get pods -n mex
(ctrl-c to exit)
```

Note that the _bitnami_ charts for OpenSearch and Redis are using their default configs, which includes replicas. These
could be pared down at the expense of some redundancy.

The `install-init` container is temporary, i.e. it runs its job and then shuts down.

## Observe the web logs

To watch the logs from e.g. all web containers (running the Invenio app):

```bash
kubectl logs -f -l app=web -n mex --max-log-requests=6
```

## Teardown

If you want to uninstall you can run:

```bash
helm uninstall mex-invenio -n mex
```

Verify they're all destroyed with `kubectl get pods -n mex`

If you're redeploying and the `install-init` pod keeps reappearing, that means it's being recreated by the job. You can
remove that explicitly via:

```bash
kubectl delete job install-init -n mex
```

Uninstalling a helm installation does not remove the 11 persistent volumes (PVs) and claims (PVCs) created. To see the
pvcs run

```bash
kubectl get pv -n mex
```

and

```bash
kubectl get pvc -n mex
```

You can delete all pvcs with this command:

```bash
kubectl delete pvc -n mex --all
```

If you're running the external postgres, you may not be able to reinstall the deployment due to the old tables persisting. Before uninstalling the release, you should log into a web or worker pod and drop the tables via the `invenio` command:

```bash
kubectl -n mex exec --stdin --tty web-57c8476cf8-2kvvt -- /bin/bash
invenio db drop
```

## Scale

To scale web or workers, you can run:

```bash
kubectl scale deployment --replicas=5 web -n mex
```

# Administration - Run commands in pods

Observe which pods we have running

    kubectl get pods -n mex

Choose a `web` pod (running the application) and execute a shell

```bash
kubectl -n mex exec --stdin --tty web-57c8476cf8-2kvvt -- /bin/bash
```

The `invenio` CLI command is available in the `web` pods, so from the default entrypoint you can manage the application.
See []() for more details.

```bash
[invenio@web-57c8476cf8-2kvvt src]$ invenio --help
Usage: invenio [OPTIONS] COMMAND [ARGS]...

  Command Line Interface for Invenio.

Options:
  -e, --env-file FILE   Load environment variables from this file. python-
                        dotenv must be installed.
  -A, --app IMPORT      The Flask application or factory function to load, in
                        the form 'module:name'. Module can be a dotted import
                        or file path. Name is not required if it is 'app',
                        'application', 'create_app', or 'make_app', and can be
                        'name(args)' to pass arguments.
  --debug / --no-debug  Set debug mode.
  --version             Show the Flask version.
  --help                Show this message and exit.

Commands:
  access          Account commands.
  alembic         Perform database migrations.
  collect         Collect static files.
  communities     Invenio communities commands.
  db              Database commands.
  domains         Domain commands.
  files           File management commands.
  identity-cache  Invenio identity cache commands.
  index           Manage search indices.
  instance        Instance commands.
  limiter         Flask-Limiter maintenance & utility commmands
  pid             PID-Store management commands.
  queues          Manage events queue.
  rdm             Invenio app rdm commands.
  rdm-records     InvenioRDM records commands.
  roles           Role commands.
  routes          Show the routes for the app.
  run             Run a development server.
  shell           Runs a shell in the app context.
  stats           Statistics commands.
  tokens          OAuth2 server token commands.
  users           User commands.
  vocabularies    Vocabularies command.
  webpack         Webpack commands
```

# Importer

There's a cron job to run the import script nightly. You can also kick it off manually via:

```bash
kubectl create job --from=cronjob/mex-invenio-import-job manual-import-$(date +%F-%H%M) -n mex
```
