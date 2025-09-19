-- db/migrations/001_init_conversation_and_rpc.sql
-- Purpose: Create conversation tables, a simple RPC used by the agent (via PostgREST),
--          and grants needed for PostgREST anonymous access.

BEGIN;

----------------------------------------------------------------------
-- 0) Role for PostgREST (idempotent)
----------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_anon') THEN
    CREATE ROLE web_anon NOLOGIN;
  END IF;
END$$;

----------------------------------------------------------------------
-- 1) Tables
----------------------------------------------------------------------

-- Tracks where each user is in the questionnaire
CREATE TABLE IF NOT EXISTS conversation_state (
  user_id         TEXT PRIMARY KEY,
  app_id          TEXT,
  current_question TEXT,
  last_updated    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE conversation_state IS
  'One row per user tracking current question and app context for the onboarding chat.';
COMMENT ON COLUMN conversation_state.user_id IS 'Chat/user identifier (from n8n Chat).';
COMMENT ON COLUMN conversation_state.app_id IS 'Application ID being onboarded.';
COMMENT ON COLUMN conversation_state.current_question IS 'Latest question asked (e.g., q1_login_flow).';
COMMENT ON COLUMN conversation_state.last_updated IS 'Server timestamp of last modification.';

-- Stores the Q&A collected from the user
CREATE TABLE IF NOT EXISTS conversation_answers (
  user_id     TEXT NOT NULL,
  question_id TEXT NOT NULL,
  answer      TEXT,
  timestamp   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, question_id)
);

COMMENT ON TABLE conversation_answers IS
  'Answers provided by users during onboarding chat; one row per (user, question).';

-- Helpful indexes for retrieval/analytics
CREATE INDEX IF NOT EXISTS idx_conv_answers_user ON conversation_answers (user_id);
CREATE INDEX IF NOT EXISTS idx_conv_answers_user_ts ON conversation_answers (user_id, timestamp DESC);

-- Optional: simple workflow event log (mirrors current flow style)
CREATE TABLE IF NOT EXISTS entra_workflow_logs (
  ts            TIMESTAMPTZ NOT NULL DEFAULT now(),
  event         TEXT NOT NULL,
  workflow      TEXT,
  node          TEXT,
  correlationid TEXT,
  status        TEXT,
  error         TEXT,
  level         TEXT
);

COMMENT ON TABLE entra_workflow_logs IS
  'Lightweight log table for n8n workflow events (optional).';

----------------------------------------------------------------------
-- 2) RPC used by the agent via PostgREST
--    Signature matches how the agent posts JSON: { user_id, app_id, question_id, answer }
--    See your manual workflow using these same tables. :contentReference[oaicite:1]{index=1}
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
AS $$
BEGIN
  -- Upsert the answer
  INSERT INTO conversation_answers (user_id, question_id, answer, timestamp)
  VALUES (user_id, question_id, answer, now())
  ON CONFLICT (user_id, question_id)
  DO UPDATE SET
    answer    = EXCLUDED.answer,
    timestamp = now();

  -- Advance/record state
  INSERT INTO conversation_state (user_id, app_id, current_question, last_updated)
  VALUES (user_id, app_id, question_id, now())
  ON CONFLICT (user_id)
  DO UPDATE SET
    app_id           = EXCLUDED.app_id,
    current_question = EXCLUDED.current_question,
    last_updated     = now();
END;
$$;

COMMENT ON FUNCTION save_answer(TEXT, TEXT, TEXT, TEXT) IS
  'RPC for n8n agent to persist an answer and update conversation state (exposed via PostgREST).';

----------------------------------------------------------------------
-- 3) Grants for PostgREST anonymous role
--    Ensure your PostgREST container uses: PGRST_DB_ANON_ROLE=web_anon
----------------------------------------------------------------------

GRANT USAGE ON SCHEMA public TO web_anon;

-- Read progress & answers as needed
GRANT SELECT ON conversation_state   TO web_anon;
GRANT SELECT ON conversation_answers TO web_anon;

-- Allow agent to write via direct table access *and* the RPC
GRANT INSERT, UPDATE ON conversation_state   TO web_anon;
GRANT INSERT, UPDATE ON conversation_answers TO web_anon;

-- Execute RPC
GRANT EXECUTE ON FUNCTION save_answer(TEXT, TEXT, TEXT, TEXT) TO web_anon;

COMMIT;
