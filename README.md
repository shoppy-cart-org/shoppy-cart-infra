# shoppy cart infra Documentation

**Ownership:** Cloud / Infrastructure Team
**Repository type:** Terraform — AWS infrastructure
**Purpose:** Provisions the AWS foundation for the Shoppy Cart platform.

---

## Table of Contents

1. [What This Repo Owns](#1-what-this-repo-owns)
2. [What This Repo Does NOT Own](#2-what-this-repo-does-not-own)
3. [Repository Structure](#3-repository-structure)
4. [Terraform Module Map](#4-terraform-module-map)
5. [Identity Model EKS Pod Identity (No OIDC/IRSA)](#5-identity-model--eks-pod-identity-no-oidcirs) 
6. [Environment Layout](#6-environment-layout)
7. [Workflow — CI and Deploy](#7-workflow--ci-and-deploy)
8. [How to Validate](#8-how-to-validate)
9. [How to Deploy](#9-how-to-deploy)
10. [How to Destroy](#10-how-to-destroy)
11. [Prerequisites](#11-prerequisites)
12. [Cost Estimate](#12-cost-estimate)
13. [Gotchas (Repo-Specific)](#13-gotchas-repo-specific)
14. [Full Doc Reference](#14-full-doc-reference)

---

## 1. What This Repo Owns

| Resource | Module | Purpose |
|---|---|---|
| VPC (3 AZs, public + private app + private data subnets) | `modules/vpc` | Network foundation |
| Internet Gateway, NAT Gateway, EIP, VPC endpoints | `modules/vpc` | Outbound internet + private ECR/S3/STS access |
| Route tables and associations | `modules/vpc` | Routing |
| 4 Security Groups (bastion, runner, ALB, EKS workers) | `modules/security-groups` | Network boundaries |
| IAM roles: `ScRunnerRole`, `ScTerraformRole`, `ScBastionRole`, `ScAppCiRole` | `modules/iam` | Human/CI identity chain |
| IAM roles: EKS cluster, EKS node | `modules/iam` | EKS control plane + nodes |
| IAM roles: EBS CSI, AWS LB Controller, ExternalDNS (Pod Identity) | `modules/iam` | Cluster addon AWS access |
| ECR: 12 private repos (immutable, scan on push) | `modules/ecr` | Container registry |
| Bastion EC2 (`t3.micro`, public subnet) | `modules/bastion` | Admin workstation |
| Runner EC2 (`t3.medium`, private subnet) | `modules/runner` | Self-hosted GitHub Actions runner |
| Key pairs: `sc-bastion-keypair`, `sc-runner-keypair` | `modules/keypair` | SSH access |
| EKS cluster v1.36 + managed node group (3 × m7i-flex.large) | `modules/eks` | Kubernetes platform |
| EKS addons: vpc-cni, coredns, kube-proxy, ebs-csi, pod-identity-agent | `modules/eks` | Cluster functions |
| EKS access entries + Pod Identity associations | `modules/eks` | Bastion admin + addon identity |
| Terraform state backend (S3) | `bootstrap/` (manual) | Remote state |
| CI/CD workflows: `terraform-ci.yml`, `terraform-deploy.yml` | `.github/workflows/` | Infra pipeline |

---

## 2. What This Repo Does NOT Own

| Concern | Where it lives |
|---|---|
| Application source code | `shoppy-cart-app` |
| Kubernetes manifests (Helm, Kustomize, ArgoCD `Application`) | `shoppy-cart-gitops` |
| ArgoCD `AppProject` governance | `shoppy-cart-platform` |
| Monitoring and logging stacks | `shoppy-cart-observability` |
| Project documentation | `shoppy-cart-docs` |

**The principle:** This repo creates the **platform** that the other repos deploy onto. It does not deploy the application itself.

---

## 3. Repository Structure

```
shoppy-cart-infra/
│
├── .github/
│   └── workflows/
│       ├── terraform-ci.yml          ← PR: fmt, validate, plan, comment
│       └── terraform-deploy.yml      ← manual: plan → approval → apply
│
├── environments/
│   └── dev/
│       ├── backend.tf                ← S3 remote state
│       ├── versions.tf               ← Terraform + provider versions
│       ├── providers.tf              ← AWS provider (region)
│       ├── variables.tf              ← input declarations
│       ├── terraform.tfvars          ← dev values
│       ├── locals.tf                 ← common tags
│       ├── main.tf                   ← composes all modules
│       └── outputs.tf                ← environment outputs
│
├── modules/
│   ├── vpc/                          ← VPC, subnets, NAT, endpoints, routes
│   ├── security-groups/              ← 4 SGs + rules
│   ├── iam/                          ← all roles, policies, instance profiles
│   ├── keypair/                      ← bastion + runner key pairs
│   ├── bastion/                      ← bastion EC2 + user_data
│   ├── runner/                       ← runner EC2 + user_data + scripts
│   └── eks/                          ← EKS cluster, nodes, addons, Pod Identity
│
├── docs/
│   ├── architecture.md               ← high-level architecture
│   ├── operations.md                 ← runbook (deploy, destroy, troubleshoot)
│   ├── adr/                          ← architecture decision records
│   └── bugs/                         ← known issues
│
├── .gitignore
├── .terraform-version
└── README.md                         ← this file (repo-level)
```

**Full doc:** https://github.com/shoppy-cart-org/shoppy-cart-docs

---

## 4. Terraform Module Map

Each module is self-contained: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`.

| Module | Depends on | Outputs consumed by |
|---|---|---|
| `vpc` | — | `security-groups`, `bastion`, `runner`, `eks` |
| `security-groups` | `vpc` | `bastion`, `runner`, `eks` |
| `iam` | — (one output from `eks` later) | `bastion`, `runner`, `eks`, `shoppy-cart-app` (via role ARN) |
| `keypair` | — | `bastion`, `runner` |
| `bastion` | `vpc`, `security-groups`, `iam`, `keypair` | — |
| `runner` | `vpc`, `security-groups`, `iam`, `keypair` | — |
| `eks` | `vpc`, `security-groups`, `iam` | `iam` (for OIDC — but we use Pod Identity, so no OIDC output) |

**Composition:** `environments/dev/main.tf` calls each module in dependency order. Modules do not reference each other directly; the environment passes outputs as inputs.

**Example (abbreviated):**

```hcl
module "vpc" { ... }
module "security_groups" { vpc_id = module.vpc.vpc_id ... }
module "iam" { ... }
module "keypair" { ... }
module "bastion" { vpc_id = module.vpc.vpc_id, bastion_sg_id = module.security_groups.bastion_sg_id, ... }
module "runner" { ... }
module "eks" { vpc_id = module.vpc.vpc_id, private_subnet_ids = module.vpc.private_app_subnet_ids, ... }
```

---

## 5. Identity Model — EKS Pod Identity (No OIDC/IRSA)

**This is critical and different from many tutorials.** This project was built on a **Builder ID AWS account** that **cannot create OIDC providers**. Therefore:

- ❌ **No IRSA** (IAM Roles for Service Accounts) — IRSA requires an OIDC provider per cluster.
- ❌ **No GitHub OIDC** — GitHub Actions cannot assume roles via OIDC.
- ✅ **EKS Pod Identity** — used for all cluster addon AWS access.
- ✅ **Instance profile + `sts:AssumeRole` chaining** — used for CI (runner role → Terraform role / App CI role).

### The Two Identity Chains

**Chain 1 — CI (runner → Terraform role):**

```
EC2 Runner (instance profile: ScRunnerRole)
    │
    │ sts:AssumeRole (in GitHub Actions workflow)
    ▼
ScTerraformRole (full infra permissions)
    │
    ▼
Terraform creates/updates AWS resources
```

**Chain 2 — Cluster addons (Pod Identity):**

```
Pod (ServiceAccount)
    │
    │ EKS Pod Identity Association (AWS-side, created by Terraform)
    ▼
IAM Role (trusts pods.eks.amazonaws.com)
    │
    ▼
AWS API (ECR, ELB, Route53, EBS)
```

**Pod Identity roles in this repo:**
| Role | ServiceAccount | Namespace | Used by |
|---|---|---|---|
| `ScEbsCsiRole` | `ebs-csi-controller-sa` | `kube-system` | EBS CSI driver |
| `ScAwsLbControllerRole` | `aws-load-balancer-controller` | `kube-system` | AWS LB Controller |
| `ScExternalDnsRole` | `external-dns` | `external-dns` | ExternalDNS |

**Key facts:**
- The trust principal for these roles is `pods.eks.amazonaws.com`.
- The trust policy includes `sts:TagSession` (required for Pod Identity).
- The `eks-pod-identity-agent` addon must be installed on the cluster.
- The Terraform `aws_eks_pod_identity_association` creates the AWS-side link. **The Kubernetes ServiceAccount must exist** — created manually or by Helm (`serviceAccount.create=true`).

**Full detail:** https://github.com/shoppy-cart-org/shoppy-cart-docs/blob/main/docs/06-credential-matrix.md

---

## 6. Environment Layout

Only `dev` is implemented. Staging/prod would follow the same pattern.

```
environments/
└── dev/
    ├── backend.tf          # S3 bucket: shoppy-cart-s3-terraform-state
    │                       # Key: dev/terraform.tfstate
    │                       # Region: eu-north-1
    │                       # Native lockfile: use_lockfile = true
    ├── versions.tf         # Terraform >= 1.10, AWS provider ~> 6.0
    ├── providers.tf        # provider "aws" { region = var.aws_region }
    ├── variables.tf        # aws_region, project_name, vpc_cidr, ...
    ├── terraform.tfvars    # values for dev
    ├── locals.tf           # common_tags = { Project, Environment, ManagedBy }
    ├── main.tf             # module calls
    └── outputs.tf          # vpc_id, subnet IDs, role ARNs, ECR URLs, etc.
```

**State:** Remote in S3 with native lockfile (Terraform >= 1.10). No DynamoDB needed.

**Tags:** Every resource gets `Project = shoppy-cart`, `Environment = dev`, `ManagedBy = Terraform`, plus `Name` per resource.

---

## 7. Workflow — CI and Deploy

### CI (`terraform-ci.yml`)

**Triggers:** `pull_request` to `main`, types `[opened, synchronize, reopened]`, paths `environments/dev/**`, `modules/**`.

**Steps:**
1. Checkout
2. Assume `ScTerraformRole` via runner instance profile (role chaining)
3. `terraform fmt -check`
4. `terraform init`
5. `terraform validate`
6. `terraform plan -out=tfplan`
7. Post plan summary as PR comment
8. Upload `tfplan` as artifact

**Condition:** PR must be from the same repo (not a fork) — protects the self-hosted runner.

### Deploy (`terraform-deploy.yml`)

**Trigger:** `workflow_dispatch` (manual), with an `apply` confirmation input.

**Jobs:**
1. **`plan`** — fresh plan from `main`, upload artifact. No approval.
2. **`apply`** — `environment: production` (approval gate), download artifact, `terraform apply tfplan`.

**Why two jobs:** The plan must be visible **before** approval. The apply uses the **exact saved plan**, not a fresh one.

**Approval gate:** GitHub Environment `production` with required reviewers. Configured in the repo's Settings → Environments.

---

## 8. How to Validate

### Locally (from laptop, before pushing)

```bash
cd environments/dev
terraform init
terraform fmt -check
terraform validate
terraform plan
```

**Expected:** No errors, a plan with the expected resource counts for the current state.

### In CI (on PR)

Push a branch, open a PR. The `Terraform CI` workflow runs automatically. The plan is posted as a comment.

**What to look for:**
- `fmt -check` passes (no formatting drift).
- `validate` passes.
- `plan` shows the expected changes.
- No `AccessDenied` errors.

### After Deploy (from bastion)

```bash
# Verify cluster
aws eks update-kubeconfig --name sc-eks-cluster --region eu-north-1
kubectl get nodes
kubectl get pods -n kube-system

# Verify ECR
aws ecr describe-repositories --region eu-north-1 \
  --query 'repositories[?starts_with(repositoryName, `shoppy-cart/`)].repositoryName'

# Verify IAM
aws iam get-role --role-name ScTerraformRole --query 'Role.Arn'
aws iam get-role --role-name ScRunnerRole --query 'Role.Arn'
aws iam get-role --role-name ScAwsLbControllerRole --query 'Role.Arn'
```

**For full per-phase checks**, see `docs/05-build-order.md` in the docs repo.

---

## 9. How to Deploy

### First-time bootstrap

The **first** `terraform apply` must be run from the laptop with the admin IAM user, because the runner and its role don't exist yet.

```bash
cd environments/dev
terraform init
terraform plan
terraform apply
```

**This creates everything:** VPC, SGs, IAM, key pairs, bastion, runner, EKS, and the ECR dependency.

**After apply:** Register the runner with GitHub (see `docs/operations.md` for the registration steps).

### Subsequent deployments (via CI/CD)

1. Make a change in a feature branch.
2. Push, open PR.
3. CI runs, plan posted.
4. Review, merge.
5. Go to **Actions → Terraform Deploy → Run workflow**, select `main`, type `apply`, run.
6. The `plan` job runs, then the `apply` job waits for approval.
7. Approve in GitHub. Apply executes.

**The runner executes the apply.** The laptop is not involved after bootstrap.

---

## 10. How to Destroy

**Order matters.** Some resources are created by ArgoCD or by the AWS LB Controller, not by Terraform, and must be deleted first.

### Step 1: Delete ALB and its security groups

**AWS Console → EC2 → Load Balancers** — delete the ALB created by the Gateway.
**AWS Console → EC2 → Security Groups** — delete the ALB SG and any SGs created by the LB Controller.

### Step 2: Delete orphaned EBS volumes

```bash
aws ec2 describe-volumes --filters Name=status,Values=available --region eu-north-1
```

Delete any orphaned volumes (Elasticsearch data, etc.).

### Step 3: `terraform destroy`

```bash
cd environments/dev
terraform destroy
```

**Type `yes`.** This destroys all Terraform-managed resources.

### Step 4: Verify

```bash
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=shoppy-cart" --region eu-north-1 --query 'Vpcs[].VpcId'
```

**Expected:** `[]` (empty).

### Step 5: Delete the S3 state bucket

```bash
aws s3 rb s3://shoppy-cart-s3-terraform-state --force
```

### Step 6: Remove the runner (if rebuilding)

GitHub org → Settings → Actions → Runners → Remove `shoppy-cart-runner-01`.

**Full runbook:** `docs/operations.md` in this repo, and `docs/08-runbooks.md` in the docs repo.

---

## 11. Prerequisites

- **AWS account** with AdministratorAccess for the bootstrap IAM user.
- **Region:** `eu-north-1`.
- **Domain + Route53 hosted zone** for `faekcorp.site` (or your domain).
- **ACM certificate** in `eu-north-1` covering `faekcorp.site` + `*.faekcorp.site`, status `ISSUED`.
- **GitHub org** (`shoppy-cart-org`) with this repo created (empty).
- **Local tools:** Terraform >= 1.10, AWS CLI v2, `git`, `ssh`.
- **AWS Budget alert** set (e.g., $50).

**Full detail:** `docs/04-prerequisites.md` in the docs repo.

---

## 12. Cost Estimate

While the platform is running:

| Resource | Approx. daily cost |
|---|---|
| EKS control plane | $2.40 |
| 3 × m7i-flex.large nodes | $5.00 |
| NAT Gateway + data | $1.20 |
| EBS volumes | $0.10 |
| Bastion (`t3.micro`) + runner (`t3.medium`) | $0.80 |
| **This repo's share** | **~$9.50 / day** |

**ALB and application observability costs are counted in the other repos.** Total project cost is ~$10–12/day.

**Destroy at the end of each session** to avoid ongoing cost.

---

## 13. Gotchas (Repo-Specific)

These are the gotchas that affect **this repo specifically**. Full list in `docs/07-gotchas.md`.

| # | Symptom | Cause | Fix |
|---|---|---|---|
| 1 | `aws sts assume-role` fails with `AccessDenied` on role chaining | Missing `sts:TagSession` in trust policy | Add `sts:TagSession` to the target role's trust policy |
| 2 | First ECR apply fails with `AccessDenied` on `ecr:CreateRepository` | IAM policy update and ECR creation race | Add `depends_on = [module.iam]` to the ECR module call |
| 3 | AWS LB Controller cannot create ALB listeners | Official policy predates `ec2:ValidateSecurityGroupQuotasForInterface` | Add the action to the LB Controller IAM policy |
| 4 | Pod Identity workloads fail with `serviceaccount not found` | Terraform association is AWS-side only | Create the SA manually (`kubectl create sa`) before Helm install |
| 5 | Bastion cannot reach EKS API | Missing SG rule (bastion → EKS API on 443) | Add the SG rule in the EKS module |
| 6 | Runner registration token required in user_data | Security risk — token must not be in code | Register the runner manually after boot (documented in `docs/operations.md`) |
| 7 | Filebeat DaemonSet 2/3 coverage | Node at pod capacity (29/29) | Scale node group or enable Prefix Delegation (see `09-whats-not-included.md`) |

**For the full 15 gotchas with more detail:** `docs/07-gotchas.md` in the docs repo.

---

## 14. Full Doc Reference

This repo is one piece of the platform. For the complete, end-to-end guide — architecture, build order, credential matrix, all 15 gotchas, runbooks, and what's not included — see the docs repo:

**https://github.com/shoppy-cart-org/shoppy-cart-doc**

| Doc | What it covers |
|---|---|
| `README.md` | The story in 2 minutes |
| `docs/01-overview.md` | What, why, 5 pillars |
| `docs/02-architecture.md` | The 7 layers |
| `docs/03-repo-structure.md` | The 5 working repos + docs |
| `docs/04-prerequisites.md` | Before you start |
| `docs/05-build-order.md` | **The 19-phase implementation guide** |
| `docs/06-credential-matrix.md` | Pod Identity, PATs, scoped credentials |
| `docs/07-gotchas.md` | The 15 lessons |
| `docs/08-runbooks.md` | Rollback, troubleshooting, cleanup |
| `docs/09-whats-not-included.md` | Honesty + next steps |

---
