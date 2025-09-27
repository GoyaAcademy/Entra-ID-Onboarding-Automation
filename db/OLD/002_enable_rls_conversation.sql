-- db/002_enable_rls_conversation.sql
-- Purpose: Enforce per-user isolation for conversation tables via RLS,
--          introduce a helper to read identity from PostgREST (JWT or header),
--          and harden the save_answer RPC to prevent spoofing.

BEGIN;

----------------------------------------------------------------------
-- 0) Safety: ensure the anon role exists (from 001 migration)
----------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_anon') THEN
    CREATE ROLE web_anon NOLOGIN;
  END IF;
END$$;

----------------------------------------------------------------------
-- 1) Helper to resolve the "request user" from PostgREST
--    Priority:
--      1) JWT claim: user_id
--      2) JWT claim: sub
--      3) Header:    X-User-Id
--      4) Header:    X-Client-Id
--      5) Header:    X-Authenticated-Userid
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION current_request_user()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $func$
  SELECT COALESCE(
    NULLIF(current_setting('request.jwt.claim.user_id', true), ''),
    NULLIF(current_setting('request.jwt.claim.sub',      true), ''),
    NULLIF(current_setting('request.header.x-user-id',   true), ''),
    NULLIF(current_setting('request.header.x-client-id', true), ''),
    NULLIF(current_setting('request.header.x-authenticated-userid', true), '')
  );
$func$;

COMMENT ON FUNCTION current_request_user() IS
  'Derives the caller identity for RLS from PostgREST (JWT claims or headers). Returns NULL if none provided.';

----------------------------------------------------------------------
-- 2) Harden the RPC so it cannot be used to write as another user
--    NOTE: We enforce that "user_id" matches the identity from current_request_user().
--          If identity is missing, we abort with an error to avoid bypassing RLS.
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION save_answer(
  user_id     TEXT,
  app_id      TEXT,
  question_id TEXT,
  answer      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
DECLARE
  req_user TEXT := current_request_user();
BEGIN
  IF req_user IS NULL THEN
    RAISE EXCEPTION 'Missing caller identity. Provide a JWT (user_id/sub) or X-User-Id header.'
      USING ERRCODE = '28000'; -- invalid_authorization_specification
  END IF;

  IF user_id IS NULL OR user_id <> req_user THEN
    RAISE EXCEPTION 'Caller identity mismatch. user_id=% does not match req_user=%', user_id, req_user
      USING ERRCODE = '28000';
  END IF;

  -- Upsert the answer (subject to RLS)
  INSERT INTO conversation_answers (user_id, question_id, answer, timestamp)
  VALUES (user_id, question_id, answer, now())
  ON CONFLICT (user_id, question_id)
  DO UPDATE SET
    answer    = EXCLUDED.answer,
    timestamp = now();

  -- Advance/record state (subject to RLS)
  INSERT INTO conversation_state (user_id, app_id, current_question, last_updated)
  VALUES (user_id, app_id, question_id, now())
  ON CONFLICT (user_id)
  DO UPDATE SET
    app_id           = EXCLUDED.app_id,
    current_question = EXCLUDED.current_question,
    last_updated     = now();
END;
$func$;

COMMENT ON FUNCTION save_answer(TEXT, TEXT, TEXT, TEXT) IS
  'RPC for agent to persist an answer and update state; enforces caller identity against user_id.';

----------------------------------------------------------------------
-- 3) Enable RLS on conversation tables and FORCE it (also for owner/definer)
----------------------------------------------------------------------
ALTER TABLE conversation_state   ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversation_answers ENABLE ROW LEVEL SECURITY;

-- FORCE makes RLS apply even to table owner / SECURITY DEFINER contexts.
ALTER TABLE conversation_state   FORCE ROW LEVEL SECURITY;
ALTER TABLE conversation_answers FORCE ROW LEVEL SECURITY;

----------------------------------------------------------------------
-- 4) RLS policies (per-user isolation)
--    Users can only see and modify rows where user_id == current_request_user()
----------------------------------------------------------------------

-- conversation_state
DROP POLICY IF EXISTS cs_select ON conversation_state;
DROP POLICY IF EXISTS cs_insert ON conversation_state;
DROP POLICY IF EXISTS cs_update ON conversation_state;

CREATE POLICY cs_select ON conversation_state
FOR SELECT
USING (user_id = current_request_user());

CREATE POLICY cs_insert ON conversation_state
FOR INSERT
WITH CHECK (user_id = current_request_user());

CREATE POLICY cs_update ON conversation_state
FOR UPDATE
USING (user_id = current_request_user())
WITH CHECK (user_id = current_request_user());

-- conversation_answers
DROP POLICY IF EXISTS ca_select ON conversation_answers;
DROP POLICY IF EXISTS ca_insert ON conversation_answers;
DROP POLICY IF EXISTS ca_update ON conversation_answers;

CREATE POLICY ca_select ON conversation_answers
FOR SELECT
USING (user_id = current_request_user());

CREATE POLICY ca_insert ON conversation_answers
FOR INSERT
WITH CHECK (user_id = current_request_user());

CREATE POLICY ca_update ON conversation_answers
FOR UPDATE
USING (user_id = current_request_user())
WITH CHECK (user_id = current_request_user());

----------------------------------------------------------------------
-- 5) Grants (web_anon role is what PostgREST uses; SELECT/INSERT/UPDATE allowed)
--    RLS further constrains access to "their" rows only.
----------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO web_anon;

GRANT SELECT, INSERT, UPDATE ON conversation_state   TO web_anon;
GRANT SELECT, INSERT, UPDATE ON conversation_answers TO web_anon;

-- Optional: logs remain append-only and non-sensitive (no RLS here).
-- If you want to block reads from anon: REVOKE SELECT ON entra_workflow_logs FROM web_anon;
GRANT INSERT ON entra_workflow_logs TO web_anon;

COMMIT;
