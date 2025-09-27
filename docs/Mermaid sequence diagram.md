sequenceDiagram
    autonumber
    participant U as User
    participant Chat as n8n Chat<br/>(Entra Onboarding Agent)
    participant Q as Questionnaire JSON<br/>(GitHub)
    participant KB as Application KB JSON<br/>(GitHub)
    participant PGR as PostgREST API
    participant DB as Postgres
    participant Fin as n8n Finalize<br/>Webhook (/webhook/entra-onboard-finalize)
    participant GH as GitHub API

    %% 1) Session start & identity
    U->>Chat: "user id 098765"
    Note right of Chat: Capture current_user_id<br/>Then immediately rehydrate state
    Chat->>PGR: GET /conversation_state?user_id=eq.098765
    PGR->>DB: SELECT conversation_state
    DB-->>PGR: state row (0..1)
    PGR-->>Chat: 200 OK (JSON state)

    %% 2) App ID confirm, persist, & KB fetch
    U->>Chat: "app id app0003"
    Chat->>Chat: Extract token & validate ^app\\d{4}$
    Chat->>PGR: POST /rpc/save_answer\n{ payload: { user_id, app_id, question_id:"application_id", answer:"app0003" } }\nHeader: X-User-Id: 098765
    PGR->>DB: select public.save_answer(payload jsonb)
    DB-->>PGR: 200 OK (upsert answers + state)
    PGR-->>Chat: 200 OK

    Chat->>KB: GET Application_Inofmation.json
    KB-->>Chat: 200 OK (KB array)
    Chat-->>U: "Found record for app0003 — Name/Custodian/Architect... Is this correct? (yes/no)"
    U-->>Chat: yes
    Chat->>PGR: POST /rpc/save_answer\n{ payload: { user_id, app_id, question_id:"application.profile", answer:{ name, custodian, architect, env, tech } } }

    %% 3) Guided Q&A loop (questionnaire-driven)
    Chat->>Q: GET questionnaire-sso-initiation-entra.json
    Q-->>Chat: 200 OK (question list)
    loop For each question needed
        Chat-->>U: Ask next question (accept numeric/label/synonyms)
        U-->>Chat: Provide answer
        Chat->>PGR: POST /rpc/save_answer\n{ payload: { user_id, app_id, question_id:"<qid>", answer:<value> } }
        PGR->>DB: save_answer(...)
        DB-->>PGR: 200 OK
        PGR-->>Chat: 200 OK
    end

    %% 4) Finalization (YAML + PR)
    Chat->>Fin: POST /webhook/entra-onboard-finalize\n{ payload: { complete:true, user_id, app_id, application_name, sso:{...}, contacts:{...}, environment, justification_text, answers:[...] } }
    Note right of Fin: Fetch YAML template, fill placeholders,<br/>branch+commit+PR via GitHub API

    Fin->>GH: GET /repos/{owner}/{repo}/git/ref/heads/main  (base ref)
    GH-->>Fin: base SHA
    Fin->>GH: POST /repos/{owner}/{repo}/git/refs          (create branch)
    GH-->>Fin: branch created
    Fin->>GH: PUT  /repos/{owner}/{repo}/contents/{path}    (commit YAML)
    GH-->>Fin: file committed
    Fin->>GH: POST /repos/{owner}/{repo}/pulls              (open PR)
    GH-->>Fin: PR URL

    Fin-->>Chat: { status:"completed", prUrl, branch, path }
    Chat-->>U: "PR opened: <url>"

    %% Alternates
    alt App ID INVALID (no contiguous app####)
        Chat-->>U: Fixed format error message (single canonical text)
        Note right of Chat: Do not fetch KB or count digits again
    else KB not found for confirmed app#### 
        Chat-->>U: "Application ID confirmed: <id>.\nNo KB record found; please provide name, custodian, architect (OS/DB/arch if known)."
        Chat->>PGR: POST /rpc/save_answer\n{ payload: { user_id, app_id, question_id:"application_id", answer:"<id>" } }
        Note right of Chat: Save user-provided fields; mark source="user"
    end
