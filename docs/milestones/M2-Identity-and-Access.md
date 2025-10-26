# M2 — Identity & Access Implementation (Service Account + Minimal Roles)

This document is **readme-safe** and ready to include in your GitHub repository.
It outlines the **M2: Identity & Access** implementation for the **Consent Broker SaaS** project on Google Cloud.
All commands are **Windows PowerShell–friendly** and verified for the environment defined in the project configuration.

---

## Scope of M2

- Create a dedicated **deployer/runtime Service Account** for Cloud Run operations.
- Assign only the **minimal required IAM roles** (least‑privilege).
- Verify that the Service Account (SA) is correctly configured for:
  - Cloud Run deployment and management
  - Artifact Registry access
  - Logging and monitoring output
  - Acting as the runtime identity in Cloud Run deployments (with **SA‑level** `iam.serviceAccountUser`)

**Acceptance Criteria:**
The Service Account exists and holds the required roles as verified by `gcloud`.  
Project‑level policies must **not** grant `iam.serviceAccountUser` to the SA; this must be on the SA resource itself.

---

## Confirmed Configuration

- Project ID: `agent-to-saas-consent-broker`
- Region: `northamerica-northeast2`
- Service Account name: `cr-deployer`
- Service Account email: `cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com`
- Owner user: `goya.ford@gmail.com`

> Note: If your user has the **roles/owner** primitive role, it will appear in verification results. Owner is broader than needed; you may keep Owner and remove redundant granular roles, or drop Owner and keep granular roles. In all cases, keep the **SA‑level** `iam.serviceAccountUser` binding for principals that deploy.

---

## Step 1 — Verify Project Context

Confirm correct project and authenticated identity.

    gcloud config set project agent-to-saas-consent-broker
    gcloud auth list

---

## Step 2 — Create the Deployer Service Account

Create the Cloud Run Deployer Service Account.

    gcloud iam service-accounts create cr-deployer --project=agent-to-saas-consent-broker --display-name="Cloud Run Deployer"

Verify creation.

    gcloud iam service-accounts describe cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com --project=agent-to-saas-consent-broker --format="table(email,displayName)"

Expected:

    EMAIL                                                             DISPLAY_NAME
    cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com  Cloud Run Deployer

---

## Step 3 — Grant Minimal Roles to the Deployer SA (Project Level)

Assign these **project‑level** roles to the Service Account.

    gcloud projects add-iam-policy-binding agent-to-saas-consent-broker --member="serviceAccount:cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com" --role="roles/run.admin"
    gcloud projects add-iam-policy-binding agent-to-saas-consent-broker --member="serviceAccount:cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com" --role="roles/artifactregistry.writer"
    gcloud projects add-iam-policy-binding agent-to-saas-consent-broker --member="serviceAccount:cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com" --role="roles/logging.logWriter"
    gcloud projects add-iam-policy-binding agent-to-saas-consent-broker --member="serviceAccount:cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com" --role="roles/monitoring.metricWriter"

---

## Step 4 — Grant "Act As" on the SA Resource (Least‑Privilege)

Grant **Service Account User** on the SA itself (not at the project level).  
This lets the deployer identity act as the runtime SA without broad impersonation.

    gcloud iam service-accounts add-iam-policy-binding cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com --project=agent-to-saas-consent-broker --member="serviceAccount:cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com" --role="roles/iam.serviceAccountUser"

Grant the same to the human owner (recommended to keep even if Owner):

    gcloud iam service-accounts add-iam-policy-binding cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com --project=agent-to-saas-consent-broker --member="user:goya.ford@gmail.com" --role="roles/iam.serviceAccountUser"

---

## Step 5 — Verification

### A) SA existence

    gcloud iam service-accounts describe cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com --project=agent-to-saas-consent-broker --format="table(email,displayName)"

### B) Project‑level role bindings (expected: **no** `iam.serviceAccountUser` here)

    gcloud projects get-iam-policy agent-to-saas-consent-broker --flatten="bindings[].members" --filter="bindings.members:serviceAccount:cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com OR bindings.members:user:goya.ford@gmail.com" --format="table(bindings.role, bindings.members)"

Typical expected rows:
- For the **SA**: `roles/run.admin`, `roles/artifactregistry.writer`, `roles/logging.logWriter`, `roles/monitoring.metricWriter`
- For the **human user**: optionally `roles/owner` (or granular roles if you chose not to keep Owner)

**Negative check (should return **no rows**):**

    gcloud projects get-iam-policy agent-to-saas-consent-broker --flatten="bindings[].members" --filter="bindings.role:roles/iam.serviceAccountUser AND bindings.members:serviceAccount:cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com" --format="table(bindings.role, bindings.members)"

### C) SA‑level policy for `iam.serviceAccountUser` (expected: SA and human user are members)

    gcloud iam service-accounts get-iam-policy cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com --project=agent-to-saas-consent-broker --format="table(bindings.role, bindings.members)"

Typical expected row:
- `roles/iam.serviceAccountUser` with members including:
  - `serviceAccount:cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com`
  - `user:goya.ford@gmail.com`

**Acceptance Criteria:**
- The SA exists.  
- The SA holds `run.admin`, `artifactregistry.writer`, `logging.logWriter`, `monitoring.metricWriter` (project level).  
- `iam.serviceAccountUser` is **absent** at the project level and **present** on the SA policy for the SA and human user.  
- (Optional) Human user may retain `roles/owner` or use granular roles.

---

## Step 6 — Optional Cleanup (Least‑Privilege Clarity)

If you keep `roles/owner` for the human user and want to remove redundant granular roles:

    gcloud projects remove-iam-policy-binding agent-to-saas-consent-broker --member="user:goya.ford@gmail.com" --role="roles/run.admin"
    gcloud projects remove-iam-policy-binding agent-to-saas-consent-broker --member="user:goya.ford@gmail.com" --role="roles/artifactregistry.writer"

Re‑verify human user bindings:

    gcloud projects get-iam-policy agent-to-saas-consent-broker --flatten="bindings[].members" --filter="bindings.members:user:goya.ford@gmail.com" --format="table(bindings.role, bindings.members)"
    gcloud iam service-accounts get-iam-policy cr-deployer@agent-to-saas-consent-broker.iam.gserviceaccount.com --project=agent-to-saas-consent-broker --format="table(bindings.role, bindings.members)"

---

## Troubleshooting

- **PERMISSION_DENIED**
  Ensure your account has `roles/owner` or appropriate IAM admin roles.

- **Bindings don't appear**
  IAM updates can take time to propagate; re‑run verification after a short delay.

- **Different runtime SA**
  Grant `iam.serviceAccountUser` on that specific SA to the deployer SA and human user as needed.

---

## Completion and Next Steps

**M2 is complete** when:
- The SA holds four project‑level roles (run.admin, artifactregistry.writer, logging.logWriter, monitoring.metricWriter).
- `iam.serviceAccountUser` is **not** granted at the project level, but **is** present on the SA policy for the SA and human user.
- (Optional) Redundant human user roles are cleaned up if Owner is retained.

**Next (M3):**
Deploy identity‑restricted Cloud Run placeholders (`consent-api`, `consent-admin`).
