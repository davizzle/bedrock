# Project Bedrock — EKS + Retail Store Sample App

This repo provisions an **EKS** cluster on AWS with **Terraform**, and deploys the **AWS Retail Store Sample App** (with **in-cluster** MySQL/Postgres/DynamoDB Local/RabbitMQ/Redis) via **GitHub Actions** (OIDC). It also sets up a **read-only** developer IAM user and Kubernetes RBAC.

> ✅ Outcome: a running microservices demo app reachable at a public ELB URL, plus secure read-only cluster access for developers.

---

## Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Repo Structure](#repo-structure)
- [Bootstrap Remote State (S3/DynamoDB)](#bootstrap-remote-state-s3dynamodb)
- [Terraform — Create Infra (Two-Pass Apply)](#terraform--create-infra-two-pass-apply)
- [GitHub Actions — OIDC & Workflows](#github-actions--oidc--workflows)
- [Deploy the App](#deploy-the-app)
- [Access the App](#access-the-app)
- [Read-Only Developer Access](#read-only-developer-access)
- [Troubleshooting](#troubleshooting)
- [Hardening & Next Steps](#hardening--next-steps)
- [Cleanup](#cleanup)
- [Dev Notes](#dev-notes)

---

## Architecture

**AWS (us-east-1)**  
- **VPC** with 3 public + 3 private subnets, NAT for egress.  
- **EKS** `1.29` (cluster name: `bedrock-eks`), 1 managed node group (`t3.medium`, 2–5 nodes), **IRSA enabled**.  
- **EKS API**: public & private enabled; public CIDRs opened during CI (tighten later).  
- **Classic ELB** fronting the `ui` Service (type `LoadBalancer`).  
- **Node SG rule** allows **NodePort (30000–32767)** from VPC CIDR → worker nodes (so ELB can reach the pods).

**Security & Access**  
- **GitHub OIDC** role (no long-lived keys) assumed by Actions.  
- **EKS Access Entries**:
  - CI/CD role → `AmazonEKSClusterAdminPolicy` (cluster scope).
  - `dev-readonly` IAM user → `AmazonEKSViewPolicy` (cluster scope).
- **K8s RBAC**: custom `ClusterRole` `readonly-with-logs` + `ClusterRoleBinding` to group `eks-viewers` (view + logs).

**Application (in-cluster deps, as required)**  
- **Services**: catalog(+MySQL), carts(+DynamoDB Local), checkout(+Redis), orders(+Postgres + RabbitMQ), ui.  
- All deployed from the **published manifest** (e.g., `v1.3.0`).

> **Two-pass Terraform:** initial apply without Kubernetes provider/RBAC, then re-enable and re-apply after the cluster exists.

---

## Prerequisites

- AWS account + admin access (or enough to create IAM/VPC/EKS/ELB/Roles).  
- **AWS CLI v2**, **kubectl**, **Terraform** (1.6+).  
- GitHub repo with **Actions enabled**.  
- (Windows users) **Git Bash** or PowerShell.

---

## Repo Structure

```
.
├─ .github/
│  └─ workflows/
│     ├─ infra.yml              # Terraform plan/apply via OIDC
│     └─ app-deploy.yml         # Deploy sample app to EKS
├─ infra/
│  └─ terraform/
│     ├─ backend.tf             # S3 + DynamoDB state config
│     ├─ providers.tf
│     ├─ variables.tf
│     ├─ vpc.tf                 # VPC + subnets + tags
│     ├─ eks.tf                 # EKS cluster, node group, access entries
│     ├─ rbac-dev.tf            # K8s RBAC (created in pass 2)
│     ├─ iam-dev.tf             # dev-readonly IAM user (optional)
│     ├─ eks_sg.tf              # NodePort SG rule (ELB → nodes)
│     ├─ outputs.tf
│     ├─ terraform.tfvars.example
│     └─ .terraform.lock.hcl    # commit this lockfile
└─ README.md
```

---

## Bootstrap Remote State (S3/DynamoDB)

Create your **S3** bucket (versioned) and **DynamoDB** lock table (once per account/region):

```bash
ACCOUNT_ID=<your_account_id>
REGION=us-east-1
BUCKET="bedrock-tfstate-${ACCOUNT_ID}-${REGION}"
TABLE="bedrock-tflock"

aws s3api create-bucket --bucket "$BUCKET" --create-bucket-configuration LocationConstraint="$REGION" --region "$REGION" || true
aws s3api put-bucket-versioning --bucket "$BUCKET" --versioning-configuration Status=Enabled
aws dynamodb create-table --table-name "$TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST --region "$REGION" || true
```

Point `backend.tf` at them.

---

## Terraform — Create Infra (Two-Pass Apply)

> First apply **without** the Kubernetes provider/RBAC (cluster doesn’t exist yet). Then re-enable them and apply again.

1) **Configure** `infra/terraform/terraform.tfvars` (copy from `.example`):
```hcl
region        = "us-east-1"
cluster_name  = "bedrock-eks"
# Optional: cicd_role_arn = "arn:aws:iam::<ACCOUNT_ID>:role/bedrock-github-oidc"
# Optional: admin_principal_arn = "arn:aws:iam::<ACCOUNT_ID>:user/admin"
```

2) **Pass 1 — create VPC/EKS/NodeGroup/AccessEntries**  
Temporarily **disable**:
- `data "aws_eks_cluster"`, `data "aws_eks_cluster_auth"`
- `provider "kubernetes"`
- K8s RBAC resources (`rbac-dev.tf`)  
(Or gate them behind a var `create_k8s_rbac=false`.)

Apply:
```bash
cd infra/terraform
terraform init
terraform apply -auto-approve
```

3) **Pass 2 — enable K8s provider + RBAC**  
Re-enable the data/provider + `rbac-dev.tf` (or set `create_k8s_rbac=true`). Apply again:

```bash
terraform apply -auto-approve
```

4) **Classic ELB → NodePort rule (important)**  
Ensure you have this rule (already included as `eks_sg.tf`):

```hcl
data "aws_vpc" "eks" { id = module.vpc.vpc_id }

resource "aws_security_group_rule" "nodeport_from_vpc" {
  type              = "ingress"
  protocol          = "tcp"
  from_port         = 30000
  to_port           = 32767
  security_group_id = module.eks.node_security_group_id
  cidr_blocks       = [data.aws_vpc.eks.cidr_block]
  description       = "Allow Classic ELB to reach NodePort on workers"
}
```

> If omitted, the ELB may stay unhealthy even when pods are ready.

---

## GitHub Actions — OIDC & Workflows

### OIDC Role in AWS (one-time)
Create `bedrock-github-oidc` IAM role with:
- **Trust**: `token.actions.githubusercontent.com` as IdP, `aud: sts.amazonaws.com`, condition limiting to your repo `repo:<owner>/<repo>:*`.
- **Policies**:
  - `AmazonEKSClusterPolicy` (includes `eks:UpdateClusterConfig` used in workflow to allow runner IP)
  - Minimal read for ELB/EC2/ASG describe (optional for debug steps)

### Workflows

- **`.github/workflows/infra.yml`**  
  - `plan` on PRs to `infra/terraform/**`, `apply` on push to `main`, and **manual** dispatch (`mode: plan|apply`).

- **`.github/workflows/app-deploy.yml`**  
  - Runs **manually** or **after infra** succeeds.  
  - Installs `kubectl`, **opens EKS endpoint** to the runner’s IP (or 0.0.0.0/0 while testing), updates kubeconfig, applies the **published** manifest (`v1.3.0` by default), waits for everything, and prints the **UI URL**.

> Ensure repo **Settings → Actions** allows GitHub Actions and gives “Read and write” workflow permissions.

---

## Deploy the App

### A) From GitHub Actions (recommended)
- Actions → **Deploy Retail Store App** → **Run workflow**  
  - `release`: `v1.3.0` (pinned) or `latest`  
  - `namespace`: `retail`  
- The job summary prints:  
  `UI URL: http://<elb-dns>`

### B) From your machine (admin access)
```bash
aws eks update-kubeconfig --name bedrock-eks --region us-east-1
kubectl create ns retail || true
kubectl -n retail apply -f "https://github.com/aws-containers/retail-store-sample-app/releases/download/v1.3.0/kubernetes.yaml"
kubectl -n retail wait --for=condition=available --timeout=10m deployment --all
```

---

## Access the App

```bash
# Get the public ELB hostname
kubectl -n retail get svc ui -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{"\n"}'
# Open in a browser
http://<that-hostname>/
```

If `EXTERNAL-IP` is `<pending>`, confirm subnet tags on **public** subnets:
- `kubernetes.io/role/elb = 1`
- `kubernetes.io/cluster/bedrock-eks = shared`

---

## Read-Only Developer Access

**User:** `dev-readonly` (created in IAM or via Terraform).  
**Access:** EKS Access Entry (`AmazonEKSViewPolicy`) + RBAC group `eks-viewers` bound to custom `readonly-with-logs`.

### Dev setup

```bash
# 1) Configure AWS CLI profile (use provided AccessKey/Secret)
aws configure --profile dev-readonly
# region: us-east-1

# 2) Generate kubeconfig & use it
AWS_PROFILE=dev-readonly aws eks update-kubeconfig --name bedrock-eks --region us-east-1 --alias bedrock-eks-view
kubectl config use-context bedrock-eks-view

# 3) Verify read-only powers
kubectl get pods -A
kubectl logs -n retail deployment/ui --tail=100
kubectl auth can-i get pods -A       # yes
kubectl auth can-i get pods/log -A   # yes
kubectl create ns test               # Forbidden
```

**Rotate** the `dev-readonly` access key periodically.

---

## Troubleshooting

**`kubectl` can’t reach EKS (timeouts, 10.x IP)**  
- Your endpoint is **private-only** (or public CIDR doesn’t include your client).  
  - Enable EKS **public endpoint** and allow your `/32` (Terraform `cluster_endpoint_public_access_cidrs`).  
  - For Actions runners, dynamically add the runner’s `/32`, or temporarily allow `0.0.0.0/0` (still IAM-auth’d).

**ELB is up but health check fails**  
- Add NodePort rule (30000–32767/TCP) from **VPC CIDR** to the **node SG** (see `eks_sg.tf`).  
- Give ELB 5–10 minutes; it can take time to mark instances `InService`.

**`EXTERNAL-IP` pending on the `ui` Service**  
- Public subnets must have tags: `kubernetes.io/role/elb=1` and cluster tag.

**Actions “skipping”**  
- Ensure workflow `if:` handles `workflow_dispatch`.  
- `workflow_run` name must **exactly** match the infra workflow name.

**Access denied**  
- OIDC role needs IAM permissions (e.g., `AmazonEKSClusterPolicy`).  
- The role/user must have an **EKS Access Entry** and K8s RBAC permitting the action.

---

## Hardening & Next Steps

- **Tighten EKS public CIDRs** from `0.0.0.0/0` to corporate/VPN/self-hosted runner IPs.  
- Replace Classic ELB with **ALB Ingress + HTTPS**: install **AWS Load Balancer Controller** (IRSA), request an **ACM** cert, set a **Route 53** record.  
- Add **metrics-server** and basic **HPAs** (e.g., `ui` 1–3 replicas on CPU).  
- Enable **EKS control plane logs** to CloudWatch.  
- Use **OIDC everywhere** (no long-lived access keys), and rotate `dev-readonly` keys.

---

## Cleanup

```bash
# Remove app
kubectl -n retail delete -f https://github.com/aws-containers/retail-store-sample-app/releases/download/v1.3.0/kubernetes.yaml
kubectl delete ns retail

# Destroy infra
cd infra/terraform
terraform destroy -auto-approve

# Empty and delete S3 state bucket, then delete DynamoDB lock table
aws s3 rm s3://bedrock-tfstate-<ACCOUNT_ID>-us-east-1 --recursive
aws s3api delete-bucket --bucket bedrock-tfstate-<ACCOUNT_ID>-us-east-1
aws dynamodb delete-table --table-name bedrock-tflock
```

---

## Dev Notes

- **.gitignore** excludes `.terraform/**`, `*.tfstate*`, `*.tfplan`, binaries, etc. Commit **`.terraform.lock.hcl`**.  
- If you accidentally committed provider binaries, rewrite history (e.g., `git filter-repo` or `git filter-branch`) to purge >100 MB blobs before pushing.

---

**Maintainer:** Cloud DevOps — InnovateMart  
**Environment:** `us-east-1` • Cluster: `bedrock-eks` • Namespace: `retail`  
**CI/CD:** GitHub Actions (OIDC) • IaC: Terraform

> Questions or improvements? Open an issue or PR.
