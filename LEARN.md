# learn.md — Quick Crash Course (n8n, Docker, PostgreSQL, PostgREST, GitHub PR)

This file gives a beginner‑friendly tour of the stack used by the
Entra Onboarding workflows and shows how all the parts fit together.
It references the two workflows, their tools, the knowledge bases, and
the finalize template/PR path as implemented in your JSON exports. 

---

## 1) What you are building

- A chat workflow in n8n that interviews an app owner, validates an
  `app####` ID, auto‑fills from an application KB, and saves answers
  into a Postgres database via PostgREST. When complete, it sends one
  JSON payload to a second workflow. :contentReference[oaicite:1]{index=1}
- A finalize workflow that receives the payload, fills a YAML template,
  commits it under `onboarding/<safeName>-<stamp>.yaml`, and opens a
  GitHub Pull Request (PR). :contentReference[oaicite:2]{index=2}

High‑level sequence:
1) Chat user provides user_id and app_id.
2) Chat validates app ID and reads the Application KB.
3) Chat loops through questionnaire and persists answers.
4) Chat posts one JSON payload to the finalize webhook.
5) Finalize fills the YAML, commits to a branch, and opens a PR.

---

## 2) Docker and Compose basics

Docker runs each service in an isolated container. Docker Compose
starts multiple containers together.

Common commands:

~~~bash
# from the Docker/ folder that contains docker-compose.yml
docker compose up -d            # start all services
docker compose ps               # list containers
docker compose logs -f          # tail logs
docker compose down             # stop and remove containers

# open a psql shell inside the Postgres container
docker compose exec postgres psql -U admin -d n8n
~~~

Tip:
- Do not hardcode secrets in YAML. Put secrets in `.env.*` files with
  placeholders and keep them private.
- Exposed ports in compose map containers to your host machine (e.g.,
  PostgREST on host port 3000, n8n on 5678).

---

## 3) PostgreSQL basics (used by the chat workflow)

PostgreSQL stores conversation state and answers.

Core objects:
- `conversation_answers`: user_id + question_id + answer + timestamp.
- `conversation_state`: user_id’s current app_id and current question,
  plus a JSON state field if you want to maintain a merged view.

You can create these using `Docker/db/bootstrap.sql`. The export of
your working RPC accepts caller identity from an HTTP header or from
the JSON payload, normalizes the answer, upserts the row, and updates
`conversation_state`. The chat workflow’s HTTP node sends the body as
`{ "payload": { ... } }` to match the RPC signature. :contentReference[oaicite:3]{index=3}

psql tips:

~~~bash
-- list schemas and tables
\dn
\dt public.*

-- view a table layout
\d+ public.conversation_state

-- query the latest state for a user
select * from public.conversation_state where user_id = '098765';
~~~

---

## 4) PostgREST basics (bridge between HTTP and PostgreSQL)

PostgREST maps HTTP to SQL.

Two patterns used here:
- Table route (GET) with filters:
  - `GET /conversation_state?user_id=eq.098765&app_id=eq.app0003`
  - The chat workflow omits empty filters so you do not get a 400
    for missing params. :contentReference[oaicite:4]{index=4}
- RPC route (POST) for writes:
  - `POST /rpc/save_answer`
  - Body is `{"payload": {...}}` because the SQL function signature is
    `save_answer(payload jsonb)`. The node sets `X-User-Id` and also
    includes `payload.user_id` for tolerance. :contentReference[oaicite:5]{index=5}

Smoke tests:

~~~bash
# read (table route)
curl -s "http://localhost:3000/conversation_state?user_id=eq.098765" | jq

# write (RPC) — header identity + payload identity
curl -i -s -X POST http://localhost:3000/rpc/save_answer \
  -H 'Content-Type: application/json' \
  -H 'X-User-Id: 098765' \
  -d '{"payload":{"user_id":"098765","app_id":"app0003","question_id":"application_id","answer":"app0003"}}'
~~~

Permissions to remember:
- PostgREST connects as `admin` (compose env) and sets role
  `web_anon`. Grant `web_anon` to `admin`, grant `USAGE` on schema
  `public` to `web_anon`, and `EXECUTE` on the RPC. Your bootstrap
  script handles this.

---

## 5) n8n basics (how the workflows run)

n8n is a low‑code automation tool. A workflow is a graph of nodes:
triggers, HTTP requests, code steps, and AI tools.

Key pieces in your chat workflow:
- **Chat Trigger**: starts on user messages. :contentReference[oaicite:6]{index=6}
- **Model**: LLM with your OpenAI credential. :contentReference[oaicite:7]{index=7}
- **Memory**: keeps a short rolling history by session id. :contentReference[oaicite:8]{index=8}
- **Agent**: the system instructions that enforce app ID validation,
  KB flow, and the final payload contract. It also requires that every
  tool call include `user_id` and `app_id` from context. :contentReference[oaicite:9]{index=9}
- **Tools**:
  - **Application KB JSON**:
    GET the app metadata KB from GitHub and cache it once. :contentReference[oaicite:10]{index=10}
  - **Questionnaire JSON**:
    GET the question set from GitHub; the agent uses the question ids. :contentReference[oaicite:11]{index=11}
  - **State: Get**:
    GET from PostgREST using `eq.` filters; omit empty params. :contentReference[oaicite:12]{index=12}
  - **State: Save**:
    POST to `/rpc/save_answer` with header `X-User-Id` and JSON body
    `{ "payload": { user_id, app_id, question_id, answer } }`.
    The node pulls args from both `$json.args` and `$fromAI('args',...)`
    so the header never ends up empty. Full response on; never error off,
    so you see real 4xx/5xx during debugging. :contentReference[oaicite:13]{index=13}
  - **Finalize Onboarding**:
    POST the final `{ payload: {...} }` to the finalize webhook. :contentReference[oaicite:14]{index=14}

Finalize workflow:
- **Webhook** receives `{ payload }`.
- **Fetch YAML Template** downloads the base template from GitHub.
- **Merge/Fill** replaces placeholders with payload values and builds
  branch name, path, and base64 content.
- **GitHub API nodes** create the branch, commit the file under
  `onboarding/<safeName>-<stamp>.yaml`, open a PR to `main`, then
  respond with the PR URL. :contentReference[oaicite:15]{index=15}

---

## 6) Knowledge bases and how the agent uses them

- **Application_Inofmation.json**  
  Source:
  https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/questionnaires/Application_Inofmation.json  
  Used to prefill name, custodian, architect, environment, and tech
  when the user provides a valid `app####` id. The agent confirms the
  match then saves mapped fields to state. If not found, it asks the
  user for those fields. Tool: Application KB JSON. :contentReference[oaicite:16]{index=16}

- **questionnaire-sso-initiation-entra.json**  
  Source:
  https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/questionnaires/questionnaire-sso-initiation-entra.json  
  Canonical question list used to drive the interview and to assign
  stable `question_id` values for persistence. Tool: Questionnaire
  JSON. :contentReference[oaicite:17]{index=17}

---

## 7) Templates and where the file goes in the repo

- **Base template**:
  `templates/entra_app_onboarding.yaml`  
  Fetched by finalize, then fields like application name, contacts,
  environment, sso properties, and justification get injected. :contentReference[oaicite:18]{index=18}

- **Generated output**:
  `onboarding/<safeName>-<stamp>.yaml`  
  The finalize code constructs a sanitized `safeName` and a timestamp
  `stamp`, writes the filled YAML to that path, commits on a branch
  `onboard/<safeName>-<stamp>`, and opens a PR. :contentReference[oaicite:19]{index=19}

---

## 8) GitHub PR crash course

- A Pull Request proposes merging changes from a feature branch into a
  base branch (here, `main`).
- The finalize workflow:
  1) Reads the base ref to get the latest `main` SHA.
  2) Creates a new branch like `onboard/<safeName>-<stamp>`.
  3) Commits the new YAML to `onboarding/...`.
  4) Opens a PR with a title/body referencing the path.
- Reviewers inspect the diff, comment, and either request changes or
  merge. After merge, the YAML lives on `main`. :contentReference[oaicite:20]{index=20}

---

## 9) Common issues and quick fixes

- **403 on POST /rpc/save_answer**  
  Ensure header `X-User-Id` is present and has no newline characters.
  Your node strips CR/LF and reads args from `$json.args` and
  `$fromAI('args',...)` to avoid empties. Also verify:
  `grant web_anon to admin;` and `grant execute on function
  public.save_answer(jsonb) to web_anon;`. :contentReference[oaicite:21]{index=21}

- **400 on GET /conversation_state**  
  Do not send empty `eq.` filters. The node’s expressions already omit
  empty params. Keep the table route (not RPC) for filters. :contentReference[oaicite:22]{index=22}

- **Agent asks for user_id repeatedly**  
  The system message requires persistent `current_user_id` and
  `current_app_id`, and the nodes always include them in tool calls.
  Keep that block intact to prevent loops. :contentReference[oaicite:23]{index=23}

- **Hidden errors**  
  During debugging, keep Full response on and Never error off in the
  write node so you can see exact PostgREST responses. :contentReference[oaicite:24]{index=24}

---

## 10) Practice exercises

Try these short tasks to build confidence:

1) Docker:
   - Start the stack.
   - Tail logs for PostgREST, then n8n.
   - Stop and start again.

2) PostgreSQL:
   - Open psql and select from `conversation_state`.
   - Insert a test row and read it back.

3) PostgREST:
   - Curl `GET /conversation_state?user_id=eq.demo`.
   - Curl `POST /rpc/save_answer` with a demo payload.

4) n8n:
   - Import the two workflows.
   - Add an OpenAI credential and a GitHub credential.
   - Run a test chat and watch State:Get/Save calls in executions.

5) GitHub:
   - Inspect the PR created by finalize.
   - Review the YAML and merge the PR in a test repo.

---

## 11) Where to learn more (official docs and guides)

- n8n Docs:
  https://docs.n8n.io
- Docker Docs:
  https://docs.docker.com
- PostgreSQL Docs:
  https://www.postgresql.org/docs
- PostgREST Docs:
  https://postgrest.org
- GitHub Pull Requests:
  https://docs.github.com/pull-requests

---

## 12) Where this guide came from

The behavior described here is based on your exported workflows:
- Chat workflow JSON: nodes, tools, system message, and HTTP targets. 
- Finalize workflow JSON: webhook shape, template fetch, branch/commit/PR. :contentReference[oaicite:26]{index=26}
The knowledge bases and template are pulled at runtime from your repo.
