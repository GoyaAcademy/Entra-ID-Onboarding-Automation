-- 1) (Optional) Ensure the target table & unique key exist (adjust table/columns if yours differ)
--    If you already have this table/constraint, you can skip or adapt.
CREATE TABLE IF NOT EXISTS public.conversation_state (
  user_id      text NOT NULL,
  app_id       text NOT NULL,
  question_id  text NOT NULL,
  answer       jsonb,
  updated_at   timestamptz DEFAULT now(),
  PRIMARY KEY (user_id, app_id, question_id)
);

-- 2) The real worker function with NON-ambiguous parameter names
CREATE OR REPLACE FUNCTION public.save_answer_v2(
  p_user_id     text,
  p_app_id      text,
  p_question_id text,
  p_answer      jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  upserted jsonb;
BEGIN
  INSERT INTO public.conversation_state AS cs (user_id, app_id, question_id, answer, updated_at)
  VALUES (p_user_id, p_app_id, p_question_id, p_answer, now())
  ON CONFLICT (user_id, app_id, question_id)
  DO UPDATE SET answer = EXCLUDED.answer, updated_at = now()
  RETURNING jsonb_build_object(
    'user_id', cs.user_id,
    'app_id', cs.app_id,
    'question_id', cs.question_id,
    'answer', cs.answer,
    'updated_at', cs.updated_at
  )
  INTO upserted;

  RETURN upserted;
END
$$;

-- 3) Thin wrapper that preserves your existing RPC signature & JSON keys
--    PostgREST keeps accepting { "user_id": "...", "app_id": "...", "question_id": "...", "answer": {...} }.
CREATE OR REPLACE FUNCTION public.save_answer(
  user_id     text,
  app_id      text,
  question_id text,
  answer      jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN public.save_answer_v2(user_id, app_id, question_id, answer);
END
$$;
