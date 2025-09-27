BEGIN;

-- Wrapper #1: 4-arg JSONB variant → delegates to your existing TEXT RPC
-- Accepts arrays/objects and stores their JSON text in the TEXT column.
CREATE OR REPLACE FUNCTION public.save_answer(
  user_id     text,
  app_id      text,
  question_id text,
  answer      jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
BEGIN
  -- delegate to the TEXT overload installed by 001/002, converting JSONB to text
  PERFORM public.save_answer(user_id, app_id, question_id,
          CASE WHEN answer IS NULL THEN NULL ELSE answer::text END);
END;
$func$;

-- Wrapper #2: single-object variant for "Prefer: params=single-object"
-- Lets you POST { "user_id": "...", "app_id": "...", "question_id": "...", "answer": <json> }
CREATE OR REPLACE FUNCTION public.save_answer(payload jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $func$
DECLARE
  v_user_id     text := payload->>'user_id';
  v_app_id      text := payload->>'app_id';
  v_question_id text := payload->>'question_id';
  v_answer      jsonb := payload->'answer';
BEGIN
  PERFORM public.save_answer(v_user_id, v_app_id, v_question_id, v_answer);
END;
$func$;

-- Make sure PostgREST anon role can call all overloads
GRANT EXECUTE ON FUNCTION public.save_answer(text, text, text, text) TO web_anon; -- from 001/002
GRANT EXECUTE ON FUNCTION public.save_answer(text, text, text, jsonb) TO web_anon;
GRANT EXECUTE ON FUNCTION public.save_answer(jsonb)                     TO web_anon;

COMMIT;
