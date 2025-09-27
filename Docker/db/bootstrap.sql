# Docker/db/bootstrap.sql (README‑safe)

The SQL below creates the required tables, role/grants, and the RPC used by the
n8n chat workflow. It is idempotent and safe to run multiple times.

- The chat workflow reads conversation state via the table endpoint
  `/conversation_state` (GET with `eq.` filters). :contentReference[oaicite:0]{index=0}
- The chat workflow persists answers via the RPC `/rpc/save_answer`
  (POST with header `X-User-Id` and JSON body `{ "payload": { ... } }`). :contentReference[oaicite:1]{index=1}
- The finalize workflow consumes the chat payload and does not require extra DB
  objects here. :contentReference[oaicite:2]{index=2}

~~~sql
-- =====================================================================
-- Entra Onboarding DB bootstrap
-- Tables, role/grants, and RPC used by n8n workflows
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

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

comment on table public.conversation_state is
  'Backing table for GET /conversation_state used by "State: Get".'; -- :contentReference[oaicite:3]{index=3}

-- ---------------------------------------------------------------------
-- PostgREST anon role & grants
-- - PostgREST connects as "admin" (from docker compose) and SET ROLE web_anon
-- ---------------------------------------------------------------------

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'web_anon') then
    create role web_anon nologin;
  end if;
end $$;

grant usage on schema public to web_anon;
grant web_anon to admin;

-- ---------------------------------------------------------------------
-- RPC: public.save_answer(payload jsonb)
-- - HTTP: POST /rpc/save_answer
-- - Body: { "payload": { user_id, app_id, question_id, answer } }
-- - Header: X-User-Id (accepted) or payload.user_id (accepted)
--   (Used by "State: Save" in chat workflow)                            -- :contentReference[oaicite:4]{index=4}
-- ---------------------------------------------------------------------

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

-- =====================================================================
-- End of bootstrap
-- =====================================================================
~~~
