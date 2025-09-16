# Prompt Catalog for Entra ID Onboarding Automation  
**Author:** n8n Architect Pro  
**Version:** 1.0.0  
**Created:** 2025-09-15  

This document contains curated prompts for use with specialized GPTs and LLMs.  
They are designed to support the demo implementation of an **Entra ID Onboarding Assistant** with **n8n, Postgres, pgvector, GitHub PR automation, and Terraform YAML templates**.  

---

## 1. Entra ID Questionnaire Prompt  

**Goal:** Generate a structured decision-tree Q&A to determine if an application should onboard via **IdP-initiated SSO** or **SP-initiated SSO**.  

**Prompt:**  

~~~ 
You are an IAM domain expert. Generate a structured questionnaire to determine whether an enterprise application should be onboarded to Microsoft Entra ID using an IdP-initiated SSO pattern or an SP-initiated SSO pattern.

Output format: JSON array.

Each entry must include:
- id (unique string)
- text (question wording)
- options (list of possible answers)
- rationale (why this question matters)
- next (list of follow-up question ids, or empty if none)

Constraints:
- No narrative or explanation outside of JSON.
- Minimum 6 questions covering login flow, SAML support, app architecture, and multi-tenancy.
~~~  

---

## 2. Vector DB Schema (pgvector) Prompt  

**Goal:** Create a **pgvector schema** for knowledge base entries, with semantic search support.  

**Prompt:**  

~~~ 
You are a database architect. Design a pgvector schema to store an IAM knowledge base that powers an n8n chatbot workflow.

Requirements:
- Each KB entry must include: id, question, answer, category, tags, embedding.
- Embedding column must support OpenAI embeddings (1536 dimensions).
- Must support filtering by category (patterns, best practices, troubleshooting).

Deliverables:
1. SQL DDL for table creation.
2. At least 5 realistic INSERT statements.
3. Demonstrate how to run a semantic search query using pgvector.

Output only SQL code with comments.
~~~  

---

## 3. YAML Template for Terraform Entra ID Onboarding Prompt  

**Goal:** Generate a **Terraform-ready YAML config** file template with placeholders.  

**Prompt:**  

~~~ 
You are a Terraform + IAM expert. Generate a YAML configuration template that will later be used by Terraform to onboard an application into Microsoft Entra ID.

YAML structure:
- application:
    id, name, environment, custodian, architect, technology (os, db, architecture)
- pattern:
    type (sso-idp or sso-sp), justification
- entra_id:
    tenant_id, client_id, redirect_urls[], reply_urls[], logout_urls[], saml_metadata_url, certificates[]
- metadata:
    createdBy, createdAt, correlationId

Constraints:
- Provide {{placeholders}} for all values.
- YAML must be valid and production-ready.
- No narrative or comments outside of YAML.
~~~  

---

## 4. Postgres Applications Table + Seed Data Prompt  

**Goal:** Define schema + demo data for application metadata.  

**Prompt:**  

~~~ 
You are a systems architect. I need SQL DDL + seed data for an "applications" table in Postgres.

Schema requirements:
- app_id SERIAL PRIMARY KEY
- app_name TEXT NOT NULL
- app_technology JSONB (with keys: os, db, architecture)
- environment ENUM: dev, qa, prod
- custodian TEXT
- architect TEXT
- created_at TIMESTAMP DEFAULT now()
- updated_at TIMESTAMP DEFAULT now()

Deliverables:
1. CREATE TABLE statement
2. 5 INSERT statements with realistic enterprise applications
   - include mix of Windows/Linux apps
   - different DBs (Postgres, Oracle, SQL Server)
   - different architectures (2-tier, 3-tier, microservices)
3. Output only SQL code with comments.
~~~  

---

## 5. GitHub PR Automation Flow Prompt  

**Goal:** Define GitHub API calls for creating a PR with a new YAML file.  

**Prompt:**  

~~~ 
You are a GitHub API integration expert. Generate a sequence of REST API requests for an automation tool (like n8n) to create a Pull Request.

Steps required:
1. Create a new branch from main
2. Add a new YAML config file
3. Commit the file
4. Open a PR into main branch
5. Assign IAM engineering team as reviewers

Constraints:
- Use GitHub REST API v3
- Output must be JSON describing each HTTP request:
  • method
  • endpoint
  • headers
  • body (with placeholders)

Do not include narrative or explanations, only JSON.
~~~  

---

## Usage Guide  

- Copy each prompt into the GPT or LLM best suited for the domain.  
- Collect outputs and feed them into the **n8n workflow design**.  
- Ensure outputs comply with internal standards before integrating.  

---
