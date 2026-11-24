# PostgreSQL 16 High Availability (HA) Cluster on Azure Kubernetes Service (AKS)

A complete, production-ready deployment of a **3-node PostgreSQL 16 High Availability (HA) cluster** on **Azure Kubernetes Service (AKS)** orchestrated by **Patroni** and backed up continuously to **Azure Blob Storage** using **pgBackRest**.

---

## Architecture Overview

```text
Local Workstation (VS Code + PowerShell)
  ├── Terraform ──────────────► Azure Cloud (Resource Group, AKS, ACR, Azure Blob Storage)
  ├── Docker (Dockerfile) ────► Azure Container Registry (ACR: pg-ha:16)
  └── kubectl (k8s/*.yaml) ───► Kubernetes Cluster (Namespace: postgres-ha)

Kubernetes Cluster (AKS)
  ├── StatefulSet + Patroni ──► Bootstrap ──► Streaming Replication (1 Leader + 2 Replicas)
  ├── HA Failover ────────────► Leader Pod Delete ──► Automatic Promotion & Rejoin
  └── pgBackRest + CronJobs ──► WAL Archiving + Full & Diff Backups ──► Azure Blob Storage
```

### Repository Structure
```text
pg-ha-aks/
├── Dockerfile                  # Custom PostgreSQL 16 + Patroni + pgBackRest image
├── .gitignore                  # Excludes .env.local, *.tfstate, and session-logs/
├── terraform/
│   ├── versions.tf             # Terraform & AzureRM provider versions
│   ├── variables.tf            # Configurable deployment variables (region, node sizes, prefixes)
│   ├── main.tf                 # Resource Group, AKS, ACR, and Storage Account resources
│   └── outputs.tf              # Exported resource names, ACR login server, and storage keys
└── k8s/
    ├── 00-namespace-rbac.yaml  # postgres-ha namespace, ServiceAccount, Role, and RoleBinding
    ├── 01-secrets.yaml         # Parameterized Secret template (pg-cluster-secrets)
    ├── 02-configmaps.yaml      # Patroni YAML template & pgBackRest Azure config
    ├── 03-services.yaml        # pg-ha-primary, pg-ha-replicas, and pg-ha-headless services
    ├── 04-statefulset.yaml     # 3-replica StatefulSet (pg-ha-node) with 50Gi Premium Disks
    └── 05-cronjob-backup.yaml  # Scheduled weekly Full & daily Differential backup CronJobs
```

---

## Prerequisites

Ensure the following tools are installed on your workstation before starting:
- **Azure CLI** (`az` >= 2.60)
- **Terraform** (`terraform` >= 1.6)
- **Docker Desktop / Engine** (`docker`)
- **Kubernetes CLI** (`kubectl`)
- **Git** (`git`) and **PowerShell 7+** (or Bash)

---

## Step 1: Clone Repository & Clean Any Existing Local State

Clone the repository and ensure no stale local Terraform states or conflicting Kubernetes contexts interfere with a fresh deployment.

```powershell
# 1. Clone the repository
git clone [https://github.com/AbdullahMahiOfficial/pg-ha-aks.git](https://github.com/AbdullahMahiOfficial/pg-ha-aks.git)
cd pg-ha-aks

# 2. Verify clean working directory (remove any leftover local state/env if re-running)
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue terraform/.terraform, terraform/terraform.tfstate*, .env.local
```

---

## Step 2: Azure Authentication & Subscription Verification

Log in to Azure and confirm the active subscription where resources will be provisioned.

```powershell
# Login to Azure
az login

# List available subscriptions and select your target subscription
az account list --output table
az account set --subscription "<YOUR_SUBSCRIPTION_NAME_OR_ID>"

# Confirm active subscription
az account show --query "{Name:name, SubscriptionId:id, State:state}" --output table
```

---

## Step 3: Provision Azure Infrastructure with Terraform

Deploy the **Resource Group**, **AKS Cluster** (2 System nodes + 3 User nodes on `Standard_D2s_v3`), **Azure Container Registry (ACR)**, and **Azure Storage Account** (`pgbackrest-repo` private container).

```powershell
cd terraform

# Initialize Terraform providers and modules
terraform init

# Validate configuration
terraform validate

# Review execution plan
terraform plan

# Apply infrastructure changes
terraform apply -auto-approve
```

### Capture Terraform Outputs & Connect `kubectl` to AKS
```powershell
# Inspect created resource names
terraform output

# Store outputs in PowerShell variables for subsequent steps
$RG_NAME      = terraform output -raw resource_group_name$AKS_NAME     = terraform output -raw aks_cluster_name
$ACR_NAME     = terraform output -raw acr_name$ACR_SERVER   = terraform output -raw acr_login_server
$STORAGE_ACCT = terraform output -raw storage_account_name$STORAGE_KEY  = terraform output -raw storage_account_key

# Return to repository root
cd ..

# Fetch AKS credentials and verify all 5 nodes are Ready
az aks get-credentials --resource-group $RG_NAME --name$AKS_NAME --overwrite-existing
kubectl get nodes -o wide
```

---

## Step 4: Build & Push Custom PostgreSQL 16 + Patroni + pgBackRest Image

Build the custom container image from `Dockerfile` and push it to your private Azure Container Registry.

```powershell
# Authenticate Docker with ACR
az acr login --name \$ACR_NAME

# Build the custom PostgreSQL 16 HA image
docker build -t "\$ACR_SERVER/pg-ha:16" .

# Push the image to ACR
docker push "\$ACR_SERVER/pg-ha:16"

# Verify the image tag exists in ACR
az acr repository show-tags --name \$ACR_NAME --repository pg-ha --output table
```

---

## Step 5: Configure Local Secrets Safely (`.env.local` & Kubernetes Secret)

Never commit plaintext passwords or Azure Storage keys to Git. Store them in `.env.local` (already ignored by `.gitignore`) and generate the live Kubernetes Secret.

```powershell
# Create .env.local with strong database passwords and Terraform storage outputs
@"
SUPERUSER_PASSWORD=StrongSuperUserPass@2026!
REPLICATION_PASSWORD=StrongReplPass@2026!
AZURE_STORAGE_ACCOUNT=\$STORAGE_ACCT
AZURE_STORAGE_KEY=\$STORAGE_KEY
AZURE_STORAGE_CONTAINER=pgbackrest-repo
"@ | Out-File -FilePath .env.local -Encoding utf8

# Load variables from .env.local into current PowerShell session
Get-Content .env.local | ForEach-Object {
    if ($_ -match "^([^=]+)=(.*)$") {
        Set-Item -Path "env:\$($matches[1])" -Value $matches[2]
    }
}
```

---

## Step 6: Deploy Kubernetes Manifests to AKS (`postgres-ha` Namespace)

Update the ACR image reference in `k8s/04-statefulset.yaml` if your ACR name differs, inject environment secrets into `k8s/01-secrets.yaml`, and apply all manifests.

```powershell
# 1. Create namespace and Patroni RBAC permissions
kubectl apply -f k8s/00-namespace-rbac.yaml

# 2. Inject secrets from environment variables and apply Kubernetes Secret
$secretYaml = Get-Content k8s/01-secrets.yaml -Raw$secretYaml = $secretYaml.Replace('${SUPERUSER_PASSWORD}', $env:SUPERUSER_PASSWORD)$secretYaml = $secretYaml.Replace('${REPLICATION_PASSWORD}', $env:REPLICATION_PASSWORD)$secretYaml = $secretYaml.Replace('${AZURE_STORAGE_ACCOUNT}', $env:AZURE_STORAGE_ACCOUNT)$secretYaml = $secretYaml.Replace('${AZURE_STORAGE_KEY}', $env:AZURE_STORAGE_KEY)$secretYaml = $secretYaml.Replace('${AZURE_STORAGE_CONTAINER}', $env:AZURE_STORAGE_CONTAINER)$secretYaml | kubectl apply -f -

# 3. Apply ConfigMaps, Services, StatefulSet, and Backup CronJobs
kubectl apply -f k8s/02-configmaps.yaml
kubectl apply -f k8s/03-services.yaml
kubectl apply -f k8s/04-statefulset.yaml
kubectl apply -f k8s/05-cronjob-backup.yaml

# 4. Monitor pods until all 3 replicas (pg-ha-node-0, 1, 2) are Running (1/1)
kubectl get pods,svc,cronjob -n postgres-ha
```

---

## Step 7: Cluster Bootstrap, Permissions & Streaming Replication Verification

Verify that Patroni has elected a primary `Leader` and synchronized the two `Replica` nodes with `0` byte lag.

```powershell
# 1. Check Patroni cluster topology (1 Leader + 2 Streaming Replicas)
kubectl exec -n postgres-ha pg-ha-node-0 -- patronictl -c /tmp/patroni.yml list

# 2. Ensure data directory permissions and replication user credentials are aligned (if needed)
kubectl exec -n postgres-ha pg-ha-node-0 -- chmod 0700 /var/lib/postgresql/data/pgdata
kubectl exec -n postgres-ha pg-ha-node-0 -- psql -U postgres -c "ALTER USER replicator WITH REPLICATION PASSWORD '\$env:REPLICATION_PASSWORD';"

# 3. Verify live Write-to-Read Streaming Replication
kubectl exec -n postgres-ha pg-ha-node-0 -- psql -U postgres -c "CREATE TABLE IF NOT EXISTS ha_test (id int PRIMARY KEY, note text); INSERT INTO ha_test VALUES (1, 'aks-patroni-ok') ON CONFLICT DO NOTHING;"
kubectl exec -n postgres-ha pg-ha-node-1 -- psql -U postgres -c "SELECT * FROM ha_test;"
```

---

## Step 8: High Availability (HA) Automatic Failover Test

Simulate a primary node crash by deleting the active `Leader` pod (`pg-ha-node-0`). Patroni will automatically promote a healthy standby replica (`pg-ha-node-1` or `pg-ha-node-2`) to `Leader` on a new timeline, and the deleted pod will rejoin as a streaming `Replica`.

```powershell
# 1. Delete the active Leader pod
kubectl delete pod -n postgres-ha pg-ha-node-0

# 2. Wait ~25 seconds for leader election and pod recovery
Start-Sleep -Seconds 25

# 3. Verify new Leader promotion and streaming status across all 3 nodes
kubectl exec -n postgres-ha pg-ha-node-1 -- patronictl -c /tmp/patroni.yml list
```

> **Note:** After failover, check `patronictl list` to see which pod is the new `Leader` (e.g., `pg-ha-node-2`). All subsequent write queries and `pgBackRest` backup commands must target the active `Leader` pod.

---

## Step 9: Configure & Verify Backups with pgBackRest (Azure Blob Storage)

Initialize the `pg-ha` stanza on Azure Blob Storage (`pgbackrest-repo`) and run both **Full** and **Differential** backups from the active `Leader` pod.

```powershell
# Identify the current active Leader pod dynamically
\$LEADER_POD = kubectl get pods -n postgres-ha -l role=master -o jsonpath="{.items[0].metadata.name}"
if (-not $LEADER_POD) {$LEADER_POD = "pg-ha-node-2" }
Write-Host "Active Leader Pod: \$LEADER_POD"

# 1. Initialize pgBackRest stanza in Azure Blob Storage
kubectl exec -n postgres-ha \$LEADER_POD -- pgbackrest --stanza=pg-ha stanza-create

# 2. Run a Full Backup
kubectl exec -n postgres-ha \$LEADER_POD -- pgbackrest --stanza=pg-ha --type=full backup

# 3. Insert new data to verify incremental changes before differential backup
kubectl exec -n postgres-ha \$LEADER_POD -- psql -U postgres -c "INSERT INTO ha_test VALUES (2, 'verified-before-diff-backup') ON CONFLICT DO NOTHING;"

# 4. Run a Differential Backup
kubectl exec -n postgres-ha \$LEADER_POD -- pgbackrest --stanza=pg-ha --type=diff backup

# 5. Verify backup repository status, WAL archives, and backup chain
kubectl exec -n postgres-ha \$LEADER_POD -- pgbackrest --stanza=pg-ha info
```

### Verify Scheduled CronJobs
```powershell
# List scheduled full (weekly) and diff (daily) backup CronJobs
kubectl get cronjobs -n postgres-ha

# Optional: Trigger an immediate manual test job from the diff backup CronJob
kubectl create job --from=cronjob/pgbackrest-diff-backup manual-diff-test -n postgres-ha
kubectl get jobs,pods -n postgres-ha
```

---

## Step 10: Cleanup / Tear Down Resources (Optional)

When you are finished testing and want to avoid ongoing Azure compute/storage charges:

```powershell
# Delete Kubernetes namespace and workloads
kubectl delete namespace postgres-ha

# Destroy all Azure infrastructure created by Terraform
cd terraform
terraform destroy -auto-approve
```
