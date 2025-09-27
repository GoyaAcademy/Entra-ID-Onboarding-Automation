```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant Chat as n8n Chat (Entra Onboarding Agent)
    participant Q as Questionnaire JSON (GitHub)
    participant KB as Application KB JSON (GitHub)
    participant PGR as PostgREST API
    participant DB as Postgres
    participant Fin as n8n Finalize Webhook (/webhook/entra-onboard-finalize)
    participant GH as GitHub API

    %% 1) Session start & identity
    U->>Chat: "user id 098765"
    Note right of Chat: Capture current_user_id then rehydrate state
    Chat->>PGR: GET /conversation_state?user_id=eq.098765
    PGR->>DB: SELECT conversation_state
    DB-->>PGR: state row (0..1)
    PGR-->>Chat: 200 OK (JSON state)

    %% 2) App ID confirm, persist, & KB fetch
    U->>Chat: "app id app0003"
    Chat->>Chat: Extract token & validate ^app\d{4}$
    Chat->>PGR: POST /rpc/save_answer
    Note right of PGR: payload: { user_id, app_id, question_id:"application_id", answer:"app0003" }.
    Note right of PGR: Header: X-User-Id: 098765
    PGR->>DB: select public.save_answer(payload jsonb)
    DB-->>PGR: 200 OK (upsert answers + state)
    PGR-->>Chat: 200 OK

    Chat->>KB: GET Application_Inofmation.json
    KB-->>Chat: 200 OK (KB array)
    Chat-->>U: Found record for app0003 — Name/Custodian/Architect... Is this correct? (yes/no)
    U-->>Chat: yes
    Chat->>PGR: POST /rpc/save_answer
    Note right of PGR: payload: { user_id, app_id, question_id:"application.profile", answer:{ name, custodian, architect, env, tech } }

    %% 3) Guided Q&A loop (questionnaire-driven)
    Chat->>Q: GET questionnaire-sso-initiation-entra.json
    Q-->>Chat: 200 OK (question list)
    loop For each needed question
        Chat-->>U: Ask next question (accept numeric/label/synonyms)
        U-->>Chat: Provide answer
        Chat->>PGR: POST /rpc/save_answer
        Note right of PGR: payload: { user_id, app_id, question_id:"<qid>", answer:<value> }
        PGR->>DB: save_answer(...)
        DB-->>PGR: 200 OK
        PGR-->>Chat: 200 OK
    end

    %% 4) Finalization (YAML + PR)
    Chat->>Fin: POST /webhook/entra-onboard-finalize
    Note right of Fin: payload includes { complete:true, user_id, app_id, application_name, sso:{...}, contacts:{...}, environment, justification_text, answers:[...] }.
    Note right of Fin: Fetch template -> fill placeholders -> branch+commit+PR
    Fin->>GH: GET /repos/{owner}/{repo}/git/ref/heads/main
    GH-->>Fin: base SHA
    Fin->>GH: POST /repos/{owner}/{repo}/git/refs
    GH-->>Fin: branch created
    Fin->>GH: PUT /repos/{owner}/{repo}/contents/{path}
    GH-->>Fin: file committed
    Fin->>GH: POST /repos/{owner}/{repo}/pulls
    GH-->>Fin: PR URL

    Fin-->>Chat: { status:"completed", prUrl, branch, path }
    Chat-->>U: PR opened: URL: https://example/pr/123

    %% (blank line here separates flow from the alt block)

    %% Alternates
    alt App ID INVALID (no contiguous app####)
        Chat-->>U: Format error: please use app0000
        Note right of Chat: Do not fetch KB or re-parse digits
    else KB not found for confirmed app####
        Chat-->>U: Application ID confirmed (ID: app0003). No KB record found.
        Chat-->>U: Please provide name, custodian, architect (OS/DB/arch if known).
        Chat->>PGR: POST /rpc/save_answer
        Note right of PGR: payload: { user_id, app_id, question_id:"application_id", answer:"app0003" }
        Note right of Chat: Save user-provided fields;
        Note right of Chat: mark source = "user"

    end
