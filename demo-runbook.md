# demo-runbook.md — How to Demo the Two Entra Onboarding Workflows (README-safe)

This runbook shows exactly how to demo the two n8n workflows:
the chat-driven **Entra Onboarding Agent** and the **Finalize** workflow
that creates a YAML and opens a GitHub Pull Request (PR).
Node wiring and behavior are based on your exported workflow JSON. 

---

## 1) What you will show

1) A user chats with the agent in n8n.
2) The agent validates `app####`, looks up the Application KB,
   asks a small questionnaire, and persists answers to PostgREST.
3) When complete, the agent calls the finalize webhook.
4) The finalize workflow fills a YAML template and opens a PR that adds
   `onboarding/<safeName>-<stamp>.yaml` to the repo.
5) You review the YAML in the PR, approve, and merge. :contentReference[oaicite:1]{index=1}

Key URLs the workflows consume:
- Questionnaire JSON:
  https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/questionnaires/questionnaire-sso-initiation-entra.json
- Application KB JSON:
  https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/questionnaires/Application_Inofmation.json
- Base YAML template:
  https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/templates/entra_app_onboarding.yaml

The chat workflow calls:
- `GET /conversation_state` with `eq.` filters to rehydrate state.
- `POST /rpc/save_answer` with `{ "payload": { ... } }` and `X-User-Id`.
- `POST /webhook/entra-onboard-finalize` with `{ "payload": { ... } }`.
All of this is visible in the workflow JSON. :contentReference[oaicite:2]{index=2}

---

## 2) Pre-demo checklist (5 minutes)

- Docker stack is up (Postgres, PostgREST, n8n).
- Database objects exist:
  - `conversation_state` and `conversation_answers` tables.
  - RPC `public.save_answer(payload jsonb)` with grants.
- n8n credentials configured:
  - OpenAI (chat model).
  - GitHub (repo write access for PR).
- Workflows imported and active as needed:
  - Chat: `entra_onboarding_agent_chat.json`. :contentReference[oaicite:3]{index=3}
  - Finalize: `entra_onboarding_finalize.json` (active; exposes webhook). :contentReference[oaicite:4]{index=4}

Tip: In the chat workflow, HTTP nodes for State:Get and State:Save are already
set to the expected endpoints and formats. :contentReference[oaicite:5]{index=5}

---

## 3) Live demo script (8–12 minutes)

### 3.1 Start the conversation

Open the n8n Chat UI and send:

~~~text
userid = 098765
~~~

Explain:
- The agent confirms the user id and immediately calls State:Get
  to rehydrate prior progress. :contentReference[oaicite:6]{index=6}

### 3.2 Provide the application id

Send:

~~~text
app id app0003
~~~

Explain:
- The agent extracts `app0003`, validates `^app\d{4}$`,
  saves `application_id` via State:Save,
  then fetches the Application KB to confirm the record. :contentReference[oaicite:7]{index=7}

When the agent shows the KB match, reply:

~~~text
y
~~~

The agent persists mapped fields (name, custodian, architect,
environment, tech) to State in one go. :contentReference[oaicite:8]{index=8}

### 3.3 Questionnaire highlights

Let the agent ask 1–3 questions (e.g., protocol, initiation type).
Answer plainly (numbers, labels, or synonyms are accepted).
Each answer is saved via `/rpc/save_answer`. :contentReference[oaicite:9]{index=9}

Examples you can use:
- Protocol: `oidc`
- Initiation: `idp initiated`
- Claims: `email, name`

### 3.4 Finalize (YAML + PR)

When the agent says it has enough info, it sends the final payload to:

~~~text
POST /webhook/entra-onboard-finalize
~~~

The finalize workflow:
- Downloads the base template.
- Fills placeholders from your payload.
- Creates branch `onboard/<safeName>-<stamp>`.
- Commits `onboarding/<safeName>-<stamp>.yaml`.
- Opens a PR and returns the PR URL to chat. :contentReference[oaicite:10]{index=10}

Copy the PR URL from the chat response.

---

## 4) PR review, YAML review, and approval (3–6 minutes)

### 4.1 Open the PR

In GitHub, open the PR created by finalize.
Point out:
- Title references the app.
- One changed file under `onboarding/`. :contentReference[oaicite:11]{index=11}

### 4.2 Review the YAML content

Click the file and review key sections against what the agent collected:

- `application_id`, `application_name`, `environment`.
- `contacts.custodian_name`, `contacts.architect_name`.
- `technology.os`, `technology.db`, `technology.architecture`.
- `sso.type`, `sso.protocol`, `sso.flow`.
- `redirect_urls`, `reply_urls`, `logout_urls` (first 1–2 entries).
- `claims` and any `saml` fields if relevant.
- `justification_text` (brief reason derived by the agent).

This mapping is performed in the finalize workflow’s Fill Template logic. :contentReference[oaicite:12]{index=12}

### 4.3 Approve and merge

Click **Approve** and **Merge**.
Explain:
- After merge, the YAML is on `main` and ready for downstream pipeline
  steps (if configured).

Optional:
- Show the branch `onboard/<safeName>-<stamp>` in the branches list.
- Show the merged file under `onboarding/` on `main`. :contentReference[oaicite:13]{index=13}

---

## 5) Optional bonus demos (2–4 minutes)

- **Invalid app id**:
  Send `id: app 0007`. The agent returns a single canonical
  format message and asks again (no digit counting chatter). :contentReference[oaicite:14]{index=14}

- **KB not found**:
  Use a valid `app####` that is not in the KB.
  The agent confirms the id, says no KB record was found,
  asks for name/custodian/architect, and saves the provided fields. :contentReference[oaicite:15]{index=15}

- **State rehydration**:
  Start a new chat with the same user id; show State:Get returning the
  last progress and the agent resuming gracefully. :contentReference[oaicite:16]{index=16}

---

## 6) Troubleshooting during a demo

- **403 on State:Save**:
  Header `X-User-Id` must be present and not contain newlines.
  The node sanitizes and merges args from `$json.args`
  and `$fromAI('args',...)` to prevent empties. :contentReference[oaicite:17]{index=17}

- **400 on State:Get**:
  Ensure empty filters are omitted. The node’s expressions already do this
  by returning `undefined` for empty values. :contentReference[oaicite:18]{index=18}

- **No PR opened**:
  Check that the finalize workflow is active and the GitHub credential
  has repo write access. The sequence of GitHub API calls is visible in
  the finalize workflow JSON. :contentReference[oaicite:19]{index=19}

---

## 7) Reset between demos

- Delete the created branch `onboard/<safeName>-<stamp>` if you want to run
  again with the same file name.
- Optionally delete the YAML from `main` in a test repo.
- Clear chat history in n8n if you want a fresh conversation context.

---

## 8) Appendix: Quick reference commands

Curl PostgREST RPC (sanity):

~~~bash
curl -i -s -X POST http://localhost:3000/rpc/save_answer \
  -H 'Content-Type: application/json' \
  -H 'X-User-Id: 098765' \
  -d '{"payload":{"user_id":"098765","app_id":"app0003","question_id":"application_id","answer":"app0003"}}'
~~~

n8n admin basics:

~~~bash
docker compose ps
docker compose logs -f n8n
~~~

Postgres psql:

~~~bash
docker compose exec postgres psql -U admin -d n8n -c "select * from public.conversation_state limit 5;"
~~~

---

## 9) Where to look in the JSON (for proof points during the demo)

- Chat workflow:
  - Agent system message rules for app id extraction and KB flow.
  - Tools: Questionnaire JSON, Application KB JSON, State:Get, State:Save,
    Finalize Onboarding with the exact endpoints and payload shapes. :contentReference[oaicite:20]{index=20}

- Finalize workflow:
  - Webhook path `entra-onboard-finalize`.
  - Template fetch, Fill Template code, GitHub branch/commit/PR,
    and Respond (PR URL). :contentReference[oaicite:21]{index=21}
