-- >>> patch_onboarding_rpc.sql  (idempotent)
BEGIN;

-- Ensure anon role (PostgREST)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'web_anon') THEN
    CREATE ROLE web_anon NOLOGIN;
  END IF;
END$$;

-- ===== 1) Tables exist with expected types =====
-- conversation_state baseline (keep your original shape)
CREATE TABLE IF NOT EXISTS public.conversation_state (
  user_id         TEXT PRIMARY KEY,
  app_id          TEXT,
  current_question TEXT,
  last_updated    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- If someone created app_id as an integer earlier, coerce to TEXT.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='conversation_state'
      AND column_name='app_id' AND data_type IN ('integer','smallint','bigint')
  ) THEN
    EXECUTE 'ALTER TABLE public.conversation_state
             ALTER COLUMN app_id TYPE TEXT USING app_id::text';
  END IF;
END$$;

-- conversation_answers with JSONB answers
CREATE TABLE IF NOT EXISTS public.conversation_answers (
  user_id     TEXT NOT NULL,
  question_id TEXT NOT NULL,
  answer      JSONB,
  timestamp   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, question_id)
);

-- If 'answer' is TEXT from an earlier migration, convert to JSONB safely.
DO $$
DECLARE
  v_type TEXT;
BEGIN
  SELECT data_type
  INTO v_type
  FROM information_schema.columns
  WHERE table_schema='public'
    AND table_name='conversation_answers'
    AND column_name='answer';

  IF v_type = 'text' THEN
    EXECUTE $sql$
      ALTER TABLE public.conversation_answers
      ALTER COLUMN answer TYPE jsonb
      USING CASE
              WHEN answer IS NULL THEN NULL
              WHEN answer ~ '^\s*[\{\[]' THEN answer::jsonb   -- already JSON-looking
              ELSE to_jsonb(answer)                            -- preserve as JSON string
            END
    $sql$;
  END IF;
END$$;

-- Helpful indexes (if not present)
CREATE INDEX IF NOT EXISTS idx_conv_answers_user       ON public.conversation_answers (user_id);
CREATE INDEX IF NOT EXISTS idx_conv_answers_user_ts    ON public.conversation_answers (user_id, timestamp DESC);

-- ===== 2) Robust current_request_user() for PG14+ / PostgREST 12 =====
-- (Replaces simple version; reads JSON GUCs & headers). Source idea in your db fix file.
CREATE OR REPLACE FUNCTION public.current_request_user()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $func$
DECLARE
  claims  jsonb := '{}'::jsonb;
  headers jsonb := '{}'::jsonb;
  v TEXT;
BEGIN
  BEGIN claims := COALESCE(current_setting('request.jwt.claims', true)::jsonb, '{}'::jsonb); EXCEPTION WHEN others THEN claims := '{}'::jsonb; END;
  IF claims ? 'user_id' THEN v := claims->>'user_id'; IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF; END IF;
  IF claims ? 'sub'     THEN v := claims->>'sub';     IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF; END IF;

  BEGIN headers := COALESCE(current_setting('request.headers', true)::jsonb, '{}'::jsonb); EXCEPTION WHEN others THEN headers := '{}'::jsonb; END;
  IF headers ? 'x-user-id'                THEN v := headers->>'x-user-id';                IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF; END IF;
  IF headers ? 'x-client-id'              THEN v := headers->>'x-client-id';              IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF; END IF;
  IF headers ? 'x-authenticated-userid'   THEN v := headers->>'x-authenticated-userid';   IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF; END IF;

  -- Legacy fallbacks (older PostgREST GUCs)
  BEGIN v := NULLIF(current_setting('request.jwt.claim.user_id', true), ''); IF v IS NOT NULL THEN RETURN v; END IF; EXCEPTION WHEN others THEN NULL; END;
  BEGIN v := NULLIF(current_setting('request.jwt.claim.sub', true), '');     IF v IS NOT NULL THEN RETURN v; END IF; EXCEPTION WHEN others THEN NULL; END;
  BEGIN v := NULLIF(current_setting('request.header.x-user-id', true), '');  IF v IS NOT NULL THEN RETURN v; END IF; EXCEPTION WHEN others THEN NULL; END;
  BEGIN v := NULLIF(current_setting('request.header.x-client-id', true), '');IF v IS NOT NULL THEN RETURN v; END IF; EXCEPTION WHEN others THEN NULL; END;
  BEGIN v := NULLIF(current_setting('request.header.x-authenticated-userid', true), ''); IF v IS NOT NULL THEN RETURN v; END IF; EXCEPTION WHEN others THEN NULL; END;

  RETURN NULL;
END;
$func$;

COMMENT ON FUNCTION public.current_request_user() IS
  'Derives caller identity (JWT claims or headers) for RLS and RPC enforcement.';

-- ===== 3) RLS (per-user isolation) =====
ALTER TABLE public.conversation_state   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_state   FORCE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_answers FORCE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cs_select ON public.conversation_state;
DROP POLICY IF EXISTS cs_insert ON public.conversation_state;
DROP POLICY IF EXISTS cs_update ON public.conversation_state;

CREATE POLICY cs_select ON public.conversation_state
  FOR SELECT USING (user_id = current_request_user());
CREATE POLICY cs_insert ON public.conversation_state
  FOR INSERT WITH CHECK (user_id = current_request_user());
CREATE POLICY cs_update ON public.conversation_state
  FOR UPDATE USING (user_id = current_request_user())
  WITH CHECK (user_id = current_request_user());

DROP POLICY IF EXISTS ca_select ON public.conversation_answers;
DROP POLICY IF EXISTS ca_insert ON public.conversation_answers;
DROP POLICY IF EXISTS ca_update ON public.conversation_answers;

CREATE POLICY ca_select ON public.conversation_answers
  FOR SELECT USING (user_id = current_request_user());
CREATE POLICY ca_insert ON public.conversation_answers
  FOR INSERT WITH CHECK (user_id = current_request_user());
CREATE POLICY ca_update ON public.conversation_answers
  FOR UPDATE USING (user_id = current_request_user())
  WITH CHECK (user_id = current_request_user());

GRANT USAGE ON SCHEMA public TO web_anon;
GRANT SELECT, INSERT, UPDATE ON public.conversation_state   TO web_anon;
GRANT SELECT, INSERT, UPDATE ON public.conversation_answers TO web_anon;

-- ===== 4) RPCs =====
-- Canonical JSONB version (worker). Returns the upserted row.
CREATE OR REPLACE FUNCTION public.save_answer(
  user_id     TEXT,
  app_id      TEXT,
  question_id TEXT,
  answer      JSONB
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
DECLARE
  req_user TEXT := current_request_user();
  upserted JSONB;
BEGIN
  IF req_user IS NULL THEN
    RAISE EXCEPTION 'Missing caller identity. Provide a JWT (user_id/sub) or X-User-Id header.'
      USING ERRCODE = '28000';
  END IF;
  IF user_id IS NULL OR user_id <> req_user THEN
    RAISE EXCEPTION 'Caller identity mismatch. user_id=% does not match req_user=%', user_id, req_user
      USING ERRCODE = '28000';
  END IF;

  INSERT INTO public.conversation_answers AS ca (user_id, question_id, answer, timestamp)
  VALUES (user_id, question_id, answer, now())
  ON CONFLICT (user_id, question_id)
  DO UPDATE SET answer = EXCLUDED.answer, timestamp = now()
  RETURNING jsonb_build_object(
    'user_id', ca.user_id,
    'app_id',  app_id,
    'question_id', ca.question_id,
    'answer', ca.answer,
    'timestamp', ca.timestamp
  )
  INTO upserted;

  INSERT INTO public.conversation_state (user_id, app_id, current_question, last_updated)
  VALUES (user_id, app_id, question_id, now())
  ON CONFLICT (user_id)
  DO UPDATE SET app_id = EXCLUDED.app_id,
                current_question = EXCLUDED.current_question,
                last_updated = now();

  RETURN upserted;
END;
$func$;

COMMENT ON FUNCTION public.save_answer(TEXT, TEXT, TEXT, JSONB)
  IS 'RPC used by the agent; enforces caller identity and stores JSON answers.';

-- Back‑compat wrapper: when "answer" arrives as a plain string, convert to JSONB.
CREATE OR REPLACE FUNCTION public.save_answer(
  user_id     TEXT,
  app_id      TEXT,
  question_id TEXT,
  answer      TEXT
) RETURNS JSONB
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
  SELECT public.save_answer($1, $2, $3,
         CASE WHEN $4 IS NULL THEN NULL ELSE to_jsonb($4) END);
$func$;

GRANT EXECUTE ON FUNCTION public.save_answer(TEXT, TEXT, TEXT, JSONB) TO web_anon;
GRANT EXECUTE ON FUNCTION public.save_answer(TEXT, TEXT, TEXT, TEXT)  TO web_anon;

COMMIT;
