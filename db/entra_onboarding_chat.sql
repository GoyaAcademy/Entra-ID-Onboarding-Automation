-- Track conversation state
CREATE TABLE conversation_state (
  user_id TEXT PRIMARY KEY,
  current_question TEXT,
  app_id INT,
  last_updated TIMESTAMP DEFAULT now()
);

-- Store user answers
CREATE TABLE conversation_answers (
  user_id TEXT,
  question_id TEXT,
  answer TEXT,
  timestamp TIMESTAMP DEFAULT now(),
  PRIMARY KEY (user_id, question_id)
);

-- Logs for auditing
CREATE TABLE workflow_logs (
  id SERIAL PRIMARY KEY,
  event TEXT,
  workflow TEXT,
  node TEXT,
  correlationId TEXT,
  status TEXT,
  error TEXT,
  timestamp TIMESTAMP DEFAULT now(),
  level TEXT CHECK (level IN ('INFO','WARN','ERROR'))
);
