-- db/003_fix_gucs_for_pg14_postgrest.sql
-- Purpose: Make current_request_user() use PostgREST JSON GUCs on PG14+,
--          with safe fallbacks for legacy GUC names on older stacks.

BEGIN;

----------------------------------------------------------------------
-- 1) Replace helper: prefer JSON GUCs, fallback to legacy names
----------------------------------------------------------------------
CREATE OR REPLACE FUNCTION current_request_user()
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
  -- Preferred: JWT claims (JSON) - PG14+ pattern
  BEGIN
    claims := COALESCE(current_setting('request.jwt.claims', true)::jsonb, '{}'::jsonb);
  EXCEPTION WHEN others THEN
    claims := '{}'::jsonb;
  END;

  IF claims ? 'user_id' THEN
    v := claims->>'user_id';
    IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF;
  END IF;

  IF claims ? 'sub' THEN
    v := claims->>'sub';
    IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF;
  END IF;

  -- Preferred: Headers (JSON) - header names are lowercased in PostgREST
  BEGIN
    headers := COALESCE(current_setting('request.headers', true)::jsonb, '{}'::jsonb);
  EXCEPTION WHEN others THEN
    headers := '{}'::jsonb;
  END;

  IF headers ? 'x-user-id' THEN
    v := headers->>'x-user-id';
    IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF;
  END IF;

  IF headers ? 'x-client-id' THEN
    v := headers->>'x-client-id';
    IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF;
  END IF;

  IF headers ? 'x-authenticated-userid' THEN
    v := headers->>'x-authenticated-userid';
    IF v IS NOT NULL AND v <> '' THEN RETURN v; END IF;
  END IF;

  -- Fallbacks for PG ≤ 13 with legacy GUCs enabled (strings with dashes)
  -- Note: PostgREST v10+ has a switch for legacy names; it’s ignored on PG14+. :contentReference[oaicite:3]{index=3}
  BEGIN
    v := NULLIF(current_setting('request.jwt.claim.user_id', true), '');
    IF v IS NOT NULL THEN RETURN v; END IF;
  EXCEPTION WHEN others THEN NULL; END;

  BEGIN
    v := NULLIF(current_setting('request.jwt.claim.sub', true), '');
    IF v IS NOT NULL THEN RETURN v; END IF;
  EXCEPTION WHEN others THEN NULL; END;

  BEGIN
    v := NULLIF(current_setting('request.header.x-user-id', true), '');
    IF v IS NOT NULL THEN RETURN v; END IF;
  EXCEPTION WHEN others THEN NULL; END;

  BEGIN
    v := NULLIF(current_setting('request.header.x-client-id', true), '');
    IF v IS NOT NULL THEN RETURN v; END IF;
  EXCEPTION WHEN others THEN NULL; END;

  BEGIN
    v := NULLIF(current_setting('request.header.x-authenticated-userid', true), '');
    IF v IS NOT NULL THEN RETURN v; END IF;
  EXCEPTION WHEN others THEN NULL; END;

  RETURN NULL;
END;
$func$;

COMMENT ON FUNCTION current_request_user() IS
  'Derives caller identity for RLS from PostgREST (JSON GUCs on PG14+: request.jwt.claims / request.headers).';

COMMIT;
