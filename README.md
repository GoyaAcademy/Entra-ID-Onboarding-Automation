# Entra Onboarding Agent — Import & Run (README-safe)

This guide shows how to import and run the two n8n workflows published in GitHub,
and explains how they use the knowledge bases, templates, and database.

GitHub workflows:
- Chat workflow: https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/workflows/entra_onboarding_agent_chat.json
- Finalize workflow: https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/workflows/entra_onboarding_finalize.json

Local copies (the JSON you provided) were used to verify node wiring and behavior. :contentReference[oaicite:0]{index=0} :contentReference[oaicite:1]{index=1}


## 0) What you will import

- **Entra Onboarding Agent (chat)**  
  An agent-driven interview that validates an application id (`app0001`), reads a
  knowledge base to prefill details, persists answers to PostgREST, and when
  complete, calls the finalize webhook with one JSON payload. :contentReference[oaicite:2]{index=2}

- **Entra Onboarding Finalize**  
  A webhook workflow that fills a YAML template, creates a Git branch, commits
  the YAML under `onboarding/`, and opens a PR in the target GitHub repo. :contentReference[oaicite:3]{index=3}


## 1) Knowledge bases (what they are and how the chat workflow uses them)

- **Application_Inofmation.json**  
  URL: https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/questionnaires/Application_Inofmation.json  
  Purpose: Application metadata KB. The chat workflow fetches this once per
  session and looks up the object whose `application.id` equals the validated
  `app####` id. On a match, it confirms with the user and then saves fields
  like name, custodian, architect, environment, and technology into State so
  YAML can be prefilled later. If no record is found, the agent asks the user
  for those values. (Tool node: “Application KB JSON”.) :contentReference[oaicite:4]{index=4}

- **questionnaire-sso-initiation-entra.json**  
  URL: https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/questionnaires/questionnaire-sso-initiation-entra.json  
  Purpose: Canonical question list that drives the interview. The agent uses
  these ids when saving answers via PostgREST, and it maps user replies to the
  canonical choice labels. (Tool node: “Questionnaire JSON”.) :contentReference[oaicite:5]{index=5}


## 2) Templates (what they are and how the finalize workflow uses them)

- **Base template: `templates/entra_app_onboarding.yaml`**  
  URL: https://github.com/GoyaAcademy/Entra-ID-Onboarding-Automation/blob/main/templates/entra_app_onboarding.yaml  
  Purpose: The finalize workflow downloads this YAML text, then replaces
  placeholders (e.g., `{{application_id}}`, `{{application_name}}`,
  `{{custodian_name}}`, `{{architect_name}}`, technology fields, SSO fields,
  justification, and audit fields). The “Fill Template” code also handles two
  redirect/reply/logout URLs, SAML metadata/certificates when present, and
  stamps audit info. :contentReference[oaicite:6]{index=6}

- **Output path: `onboarding/${safeName}-${stamp}.yaml`**  
  Meaning:
  - `safeName` is derived from `app_id` (or `application_name` as fallback)
    and sanitized to `[a-zA-Z0-9._-]`.
  - `stamp` is an ISO-like timestamp with `:` and `T` replaced by `-` for
    filename safety.
  The finalize workflow writes the filled YAML here, on a new branch named
  `onboard/${safeName}-${stamp}`, and opens a PR against `main`. :contentReference[oaicite:7]{index=7}


## 3) Import steps (n8n)

1) In n8n, go to **Workflows > Import from URL** (or import from a local file):
   - Chat workflow: `entra_onboarding_agent_chat.json`
   - Finalize workflow: `entra_onboarding_finalize.json`  
   The imported nodes, URLs, and expressions will match the behavior outlined
   here. :contentReference[oaicite:8]{index=8} :contentReference[oaicite:9]{index=9}

2) Add **Credentials**:
   - **OpenAI** credential for the chat Model node. :contentReference[oaicite:10]{index=10}
   - **GitHub** credential with repo write access for the finalize GitHub
     requests. :contentReference[oaicite:11]{index=11}

3) Confirm **endpoints** the workflows call:
   - PostgREST base: `http://postgrest:3000`
     - Chat workflow “State: Get”: `GET /conversation_state` with `eq.` filters,
       omitting empty params. :contentReference[oaicite:12]{index=12}
     - Chat workflow “State: Save”: `POST /rpc/save_answer` with header
       `X-User-Id` and JSON body wrapped as `{ "payload": { ... } }`. The node
       reads args from both `$json.args` and `$fromAI('args',...)` to avoid
       missing-id issues. :contentReference[oaicite:13]{index=13}
   - Finalize webhook: `http://localhost:5678/webhook/entra-onboard-finalize`
     (called by the chat workflow’s “Finalize Onboarding” tool). :contentReference[oaicite:14]{index=14}


## 4) What each workflow does (concise overview)

### Chat workflow (agent-led interview)
- Validates application id by **extracting** the first `app####` token from the
  user’s message, then **validates** it matches `^app\d{4}$`. If valid, it
  immediately saves `application_id` and proceeds to KB lookup. If invalid, it
  returns one fixed format error message and asks again. :contentReference[oaicite:15]{index=15}
- Fetches the **Application KB** and confirms the matched record; on **yes**, it
  saves the mapped fields; on **no** or not found, it asks the user to provide
  those fields and saves them. No hallucinations. :contentReference[oaicite:16]{index=16}
- Persists answers via **State: Save** on every step. The node sanitizes
  `X-User-Id`, supports alias keys (`user_id`, `userId`, `user id`, etc.), and
  wraps the body under `payload`. :contentReference[oaicite:17]{index=17}
- When ready, constructs the **final payload** and posts it to the finalize
  webhook. The payload includes `sso.type`, `protocol`, URLs, contacts,
  environment, `justification_text`, and a list of raw Q&A entries. :contentReference[oaicite:18]{index=18}

### Finalize workflow (YAML + PR)
- Receives `{ payload: {...} }`, downloads the base YAML template, and fills
  placeholders using the provided fields and the SSO details. :contentReference[oaicite:19]{index=19}
- Creates a branch `onboard/${safeName}-${stamp}`, commits the filled YAML to
  `onboarding/${safeName}-${stamp}.yaml`, opens a PR to `main`, and responds
  with the PR URL. :contentReference[oaicite:20]{index=20}


## 5) Database objects (creation script)

If your database does not yet have the required tables and RPC, run the SQL
below exactly as written (idempotent). If your environment requires different
schemas or additional columns, tell me what they are and I will adapt the SQL.

~~~sql
-- tables ---------------------------------------------------------------

create table if not exists public.conversation_answers (
  user_id      text        not null,
  question_id  text        not null,
  answer       jsonb       not null,
  "timestamp"  timestamptz not null default now(),
  constraint conversation_answers_pk primary key (user_id, question_id)
);

create table if not exists public.conversation_state (
  user_id          text        primary key,
  app_id           text,
  current_question text,
  last_updated     timestamptz not null default now(),
  state            jsonb
);

-- role and grants ------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'web_anon') then
    create role web_anon nologin;
  end if;
end $$;

grant usage on schema public to web_anon;
grant web_anon to admin;

-- rpc: save_answer(payload jsonb) --------------------------------------
-- exact function body you provided

create or replace function public.save_answer(payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_user_id     text  := nullif(trim(payload->>'user_id'), '');
  v_app_id      text  := payload->>'app_id';
  v_question_id text  := payload->>'question_id';
  v_answer      jsonb := (payload->'answer')::jsonb;

  h_user   text := nullif(current_setting('request.header.x-user-id', true), '');
  req_user text;
  out_doc  jsonb;
  v_text   text;
  v_items  text[];
begin
  if h_user is null and v_user_id is null then
    raise exception 'Missing caller identity. Provide X-User-Id header or payload.user_id.'
      using errcode = '28000';
  end if;

  if h_user is not null and v_user_id is not null and h_user <> v_user_id then
    raise exception 'Caller identity mismatch. user_id=%, header=%', v_user_id, h_user
      using errcode = '28000';
  end if;

  req_user := coalesce(h_user, v_user_id);
  v_user_id := req_user;

  if v_answer is not null and jsonb_typeof(v_answer) = 'string' then
    v_text := v_answer #>> '{}';
    if v_text ~ '^\s*=' then
      v_text  := regexp_replace(v_text, '^\s*=', '');
      v_items := regexp_split_to_array(v_text, '\s*,\s*');
      v_answer := to_jsonb(v_items);
    elsif v_text ~ '^\s*(\[|\{)' then
      begin
        v_answer := to_jsonb(v_text::json);
      exception when others then
        v_answer := to_jsonb(v_text);
      end;
    else
      v_answer := to_jsonb(v_text);
    end if;
  end if;

  insert into public.conversation_answers as ca (user_id, question_id, answer, "timestamp")
  values (v_user_id, v_question_id, v_answer, now())
  on conflict (user_id, question_id)
  do update set answer = excluded.answer, "timestamp" = now()
  returning jsonb_build_object(
    'user_id',     ca.user_id,
    'app_id',      v_app_id,
    'question_id', ca.question_id,
    'answer',      ca.answer,
    'timestamp',   ca."timestamp"
  )
  into out_doc;

  insert into public.conversation_state as cs (user_id, app_id, current_question, last_updated)
  values (v_user_id, v_app_id, v_question_id, now())
  on conflict (user_id)
  do update set app_id = excluded.app_id,
               current_question = excluded.current_question,
               last_updated = now();

  return out_doc;
end
$function$;

grant execute on function public.save_answer(jsonb) to web_anon;
~~~


## 6) Minimal endpoint checks (optional)

Use these only if you need to validate connectivity. Adjust hosts if your
network differs.

~~~bash
# PostgREST should expose the RPC at localhost:3000
curl -i -s -X POST http://localhost:3000/rpc/save_answer \
  -H 'Content-Type: application/json' \
  -H 'X-User-Id: 098765' \
  -d '{"payload":{"user_id":"098765","app_id":"app0003","question_id":"application_id","answer":"app0003"}}'
~~~


## 7) Run the flows end-to-end

1) Start the chat in n8n and send:
   - `user id 098765` (agent confirms and calls State: Get)
   - `app id app0003` (agent confirms and looks up KB)
   - `y` (agent saves and continues)

2) When the agent finalizes, it posts the **final payload** to the finalize
   webhook, which fills the template and opens a PR. You will see the PR URL in
   the chat reply. :contentReference[oaicite:21]{index=21}


## 8) Notes and troubleshooting

- **Why `conversation_state` is a table endpoint (not RPC) in State: Get**  
  The chat workflow filters it with `eq.` query params and omits empty params to
  avoid bad requests. :contentReference[oaicite:22]{index=22}

- **Why `save_answer` wraps the body under `payload`**  
  The RPC signature is `save_answer(payload jsonb)`, so the HTTP body must be
  `{ "payload": { ... } }`. The node also sanitizes `X-User-Id` and accepts id
  aliases to prevent empty-header failures. :contentReference[oaicite:23]{index=23}

- **Finalize template replacement and file naming**  
  The code fills placeholders from the payload, then writes to
  `onboarding/${safeName}-${stamp}.yaml` on a new branch, and opens a PR. :contentReference[oaicite:24]{index=24}


---

