# Privacy Policy

This repository is used as a knowledge base for the **n8n Architect Pro** custom GPT.  
The associated Action integration with GitHub is configured for **read-only access**.

---

## 🔒 What Data Is Accessed
- The GPT fetches repository files (e.g., `knowledge-index.json`, standards, playbooks, docs).  
- All requests are limited to this repository: **gfatgithub/n8n-Architect-Pro**.  
- No other GitHub repositories or user data are accessed.

---

## 🚫 What Data Is Not Collected
- No personal information, secrets, or tokens are collected or stored.  
- No data is shared with third parties.  
- The GPT does not perform write operations (no commits, PRs, or issue creation).

---

## 🔑 Authentication
- A fine-grained GitHub Personal Access Token (PAT) is used.  
- Scope: **Repository → Contents: Read** only.  
- The PAT is stored securely by OpenAI as an API key for the Action.  
- Users do not need to provide their own credentials.

---

## 📚 Usage Context
- This GPT uses the repository purely for **knowledge retrieval**.  
- Content is base64-decoded and used to inform responses.  
- Updates to the repository are reflected automatically.

---

## 📌 Contact
For questions about this policy, please contact the repository owner at **https://github.com/gfatgithub**.
