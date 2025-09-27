CREATE TABLE IF NOT EXISTS public.entra_workflow_logs (
  id            BIGSERIAL PRIMARY KEY,
  event         TEXT        NOT NULL,
  workflow      TEXT        NOT NULL,
  node          TEXT        NOT NULL,
  correlationid TEXT,
  status        TEXT        NOT NULL,
  error         TEXT,
  level         TEXT        NOT NULL CHECK (level IN ('INFO','WARN','ERROR')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_entra_workflow_logs_created_at     ON public.entra_workflow_logs (created_at);
CREATE INDEX IF NOT EXISTS idx_entra_workflow_logs_workflow       ON public.entra_workflow_logs(workflow);
CREATE INDEX IF NOT EXISTS idx_entra_workflow_logscorrelationid  ON public.entra_workflow_logs (correlationid);
