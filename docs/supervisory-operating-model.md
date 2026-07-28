# Codex, Paperclip, and Hermes supervisory operating model

## Control planes

Paperclip is the company operating system: it owns companies, goals, projects, issues, dependencies, approvals, comments, artifacts, employee identity, and the durable audit trail. Hermes is the employee runtime: each Paperclip employee has a separate Hermes home, workspace, session/memory state, exact role bundle, constrained tool set, and Docker execution identity.

Codex is deliberately outside both systems. It is the platform supervisor and commissioning authority on the VM. It can inspect and change systemd, Docker, networking, installed code, backups, Paperclip board state, employee profiles, and emergency controls. That access is root-equivalent and must remain an operator capability, not a normal company employee credential.

## Responsibility split

| Actor | Normal responsibility | Must not become |
|---|---|---|
| Agency Director | decompose work, assign Core employees, integrate evidence, request decisions, close work | unrestricted host administrator, specialist substitute, or self-approving board |
| Brand and Brief Steward | normalize authorised brand evidence and make the brief executable | strategist, producer, publisher, or approval resolver |
| Search and Content Strategist | build source-aware search/content strategy and handoff artifacts | content producer, publisher, or broad delegator |
| Content Producer | create the draft from approved brief and strategy artifacts | self-reviewer, publisher, or board approver |
| Search and Answer Optimiser | improve discoverability and answer quality within the approved claims | claim inventor, self-approver, or publisher |
| Editorial Integrity QA | independently test claims, provenance, policy, accessibility, and acceptance criteria | author and sole approver of the same output |
| Publishing Operator | stage or apply only an exactly approved publication action and reconcile the result | editor, approver, or autonomous live publisher |
| Growth Intelligence Analyst | measure outcomes, lineage, uncertainty, and learning recommendations | spend controller, publisher, or retroactive evidence editor |
| Paperclip board/operator | answer interactions, approve/reject governed requests, set company policy | hidden bypass around the audit trail |
| Codex supervisor | platform engineering, audits, recovery, patching, factory maintenance, cross-layer diagnosis | routine employee doing untracked client work |

## Authority and audit

Codex can stop or resume the employee plane with `/opt/paperclip/ops/paperclip-emergency-control`, and it can use the root-only board client. These powers are intentionally stronger than Hermes employee permissions. API actions are recorded in Paperclip; host actions rely on systemd/journal, filesystem permissions, and the commissioning evidence set. Material host changes therefore require a corresponding runbook/patch/evidence update.

Hermes employees never receive the root board credential, Docker socket, host browser, host shell, backup key, or other employees' profile state. Their Paperclip identity is run-scoped. Specialists cannot create agents or skills, and only the Agency Director can assign work. Human/board gates cannot be resolved by agent actors.

## Clone boundary

Codex itself is not baked into a client company as an autonomous always-on super-employee. The image contains platform tooling and documented supervisory procedures; a trusted operator invokes Codex when needed. Any client clone must receive new instance identity, host identity, Paperclip secrets, Hermes provider credentials, backup key, and off-host namespace before use.
