# Docker Environment Setup & File Locations (README‑safe)

This document explains **where to place files** and **how to run** the Docker
environment that your n8n chat and finalize workflows expect. It aligns with the
workflows’ network endpoints and data flow (PostgREST at `postgrest:3000`,
n8n webhook at `localhost:5678/webhook/entra-onboard-finalize`). :contentReference[oaicite:0]{index=0} :contentReference[oaicite:1]{index=1}

---

## 1) Folder layout to copy into your repo

Create a top‑level `Docker/` folder and use this structure:

~~~text
Docker/
  docker-compose.yml
  .env
  .env.postgres
  .env.postgrest
  .env.n8n
  db/
    bootstrap.sql         # database tables, role/grants, RPC (save_answer)
  volumes/
    n8n/                  # optional: host bind for n8n data (if you prefer)
    pgdata/               # optional: host bind for Postgres data (if you prefer)
~~~

> You can bind `volumes/` to host directories or let Docker-managed volumes
> handle data (as in the compose file below).

---

## 2) Files to create (copy‑paste as new files)

### 2.1 `Docker/.env`

- Project‑level defaults that are **safe to commit**.

~~~text
COMPOSE_PROJECT_NAME=entra-onboarding
TZ=UTC
~~~

### 2.2 `Docker/.env.postgres`

- Postgres DB name/user are pre‑set to match the workflows.
- Replace placeholders with strong secrets before running.

~~~text
POSTGRES_DB=n8n
POSTGRES_USER=admin
POSTGRES_PASSWORD=__REPLACE_WITH_STRONG_PASSWORD__
PGDATA=/var/lib/postgresql/data
~~~

### 2.3 `Docker/.env.postgrest`

- PostgREST connects to Postgres using the same credentials as above.
- The workflows talk to PostgREST at `postgrest:3000` in Docker’s network. :contentReference[oaicite:2]{index=2}

~~~text
PGRST_DB_URI=postgres://admin:__REPLACE_WITH_STRONG_PASSWORD__@postgres:5432/n8n
PGRST_DB_ANON_ROLE=web_anon
PGRST_DB_SCHEMAS=public
PGRST_SERVER_PORT=3000
~~~

### 2.4 `Docker/.env.n8n`

- Use strong secrets; keep this file private.
- n8n runs on `http://localhost:5678` by default (editor and webhooks). :contentReference[oaicite:3]{index=3}

~~~text
# Editor auth (strongly recommended)
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=__REPLACE_WITH_USERNAME__
N8N_BASIC_AUTH_PASSWORD=__REPLACE_WITH_STRONG_PASSWORD__

# Encryption for stored credentials
N8N_ENCRYPTION_KEY=__REPLACE_WITH_LONG_RANDOM_STRING__

# Host/URLs for local dev
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_EDITOR_BASE_URL=http://localhost:5678/
WEBHOOK_URL=http://localhost:5678/
TZ=UTC
GENERIC_TIMEZONE=${TZ}

# Cookie/CSRF for local HTTP
N8N_SECURE_COOKIE=false
N8N_SESSION_COOKIE_SAME_SITE=lax

# Optional CORS during testing
N8N_CORS_ALLOW_ORIGIN=*

# Database connection (to Postgres service)
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=postgres
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=admin
DB_POSTGRESDB_PASSWORD=__REPLACE_WITH_STRONG_PASSWORD__

# n8n data path (container)
DATA_FOLDER=/home/node/.n8n
~~~

### 2.5 `Docker/docker-compose.yml`

- Three services: **postgres**, **postgrest**, **n8n** (no GitHub runner/service).
- Ports: Postgres `5432`, PostgREST `3000`, n8n `5678`.

~~~yaml
version: "3.9"

services:
  postgres:
    image: postgres:15
    container_name: entra_postgres
    env_file:
      - .env.postgres
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $$POSTGRES_USER -d $$POSTGRES_DB || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 10

  postgrest:
    image: postgrest/postgrest:v12.2.5
    container_name: entra_postgrest
    depends_on:
      postgres:
        condition: service_healthy
    env_file:
      - .env.postgrest
    ports:
      - "3000:3000"

  n8n:
    image: n8nio/n8n:latest
    container_name: entra_n8n
    depends_on:
      - postgres
      - postgrest
    env_file:
      - .env.n8n
    ports:
      - "5678:5678"
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  pgdata:
  n8n_data:
~~~

---

## 3) Database bootstrap (one‑time)

Create `Docker/db/bootstrap.sql` and place your schema objects there. If you
want me to generate the exact SQL you run in production (tables, role/grants,
and your `save_answer(payload jsonb)` function), tell me and I will insert your
function body verbatim. Otherwise, keep a standard, idempotent bootstrap here.

Apply it:

~~~bash
# from the Docker/ folder
docker compose up -d

# copy and apply bootstrap.sql into the postgres container
docker cp db/bootstrap.sql entra_postgres:/var/lib/postgresql/data/bootstrap.sql
docker compose exec postgres psql -U admin -d n8n -v ON_ERROR_STOP=1 -f /var/lib/postgresql/data/bootstrap.sql
~~~

> The chat workflow expects a table endpoint `conversation_state` (for GET with
> `eq.` filters) and an RPC `public.save_answer(payload jsonb)` exposed via
> `/rpc/save_answer`. :contentReference[oaicite:4]{index=4}

---

## 4) Start/stop and health checks

~~~bash
# start
docker compose up -d

# view status
docker compose ps

# follow logs (Ctrl+C to exit)
docker compose logs -f

# stop services
docker compose down
~~~

Check n8n: open http://localhost:5678 (use the editor credentials you set).  
Check PostgREST: smoke test the RPC:

~~~bash
curl -i -s -X POST http://localhost:3000/rpc/save_answer \
  -H 'Content-Type: application/json' \
  -H 'X-User-Id: 098765' \
  -d '{"payload":{"user_id":"098765","app_id":"app0003","question_id":"application_id","answer":"app0003"}}'
~~~

Expect `HTTP/1.1 200 OK` and a small JSON body echo if the DB function and
grants are in place.

---

## 5) Import the n8n workflows

In n8n:
1) **Workflows → Import from URL or File**:
   - Chat: `entra_onboarding_agent_chat.json`
   - Finalize: `entra_onboarding_finalize.json`
2) Add **OpenAI** credential (for the chat Model) and **GitHub** credential
   (for the finalize API calls).
3) The chat workflow calls:
   - `GET http://postgrest:3000/conversation_state` with `eq.` filters (omits
     empty params). :contentReference[oaicite:5]{index=5}
   - `POST http://postgrest:3000/rpc/save_answer` with header `X-User-Id` and
     JSON body `{ "payload": { ... } }`. :contentReference[oaicite:6]{index=6}
4) The finalize workflow exposes the webhook:
   - `POST http://localhost:5678/webhook/entra-onboard-finalize`, fills the base
     template, writes `onboarding/<safeName>-<stamp>.yaml`, and opens a PR. :contentReference[oaicite:7]{index=7}

---

## 6) File locations summary

- **Compose & env files**: `Docker/docker-compose.yml`, `.env*`  
- **Database bootstrap**: `Docker/db/bootstrap.sql`  
- **n8n data (inside container)**: `/home/node/.n8n` (mounted by volume)  
- **Postgres data (inside container)**: `/var/lib/postgresql/data`  
- **Finalize output path in repo (PR content)**:
  - Base template fetched from repo: `templates/entra_app_onboarding.yaml`  
  - Generated file path: `onboarding/<safeName>-<stamp>.yaml` (branch:
    `onboard/<safeName>-<stamp>`). :contentReference[oaicite:8]{index=8}

---

## 7) Notes

- The chat workflow’s system message and tools enforce App ID token extraction
  and validation, KB lookup, and persistent inclusion of `user_id`/`app_id`
  in tool calls; keep those endpoints stable to avoid drift. :contentReference[oaicite:9]{index=9}
- During debugging, leave “Full response = ON” and “Never error = OFF” on the
  PostgREST write node so you see exact errors if something changes. :contentReference[oaicite:10]{index=10}
