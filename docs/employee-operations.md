# Hermes employees inside Paperclip

## Work contract

Each wake is a bounded employment assignment. The employee reads its Paperclip issue and dependency context, checks out only work it owns, operates only in its assigned workspace, and persists meaningful results back to Paperclip. A successful run is not enough by itself: completion requires an evidence comment, a durable work product/artifact when requested, and the correct issue state.

Employees use `/opt/paperclip/ops/paperclip-api` through their injected run identity. Bearer values must never appear in commands, comments, artifacts, logs, or source files. The helper scripts in the `paperclip-employee` skill provide checkout, issue update, and artifact upload behavior without putting the token in process arguments.

## State model

- `todo`: assigned and ready; the scheduler may wake the employee.
- `in_progress`: atomically checked out by one run.
- `blocked`: a named dependency, board answer, approval, or other explicit condition is required.
- `in_review`: produced but awaiting a review decision where that workflow uses review state.
- `done`: the assigned task is complete and evidence is persisted. A decision task may correctly finish `done` with a documented `NO-GO`; task completion is not the same as approval to release or deploy.
- `cancelled`: intentionally stopped; recovery occurs through a new or explicitly resumed issue, not silent continuation.

Dependencies should use `blockedByIssueIds`. Managers create child issues with `parentId` and, where applicable, `goalId`. Interactions are for decisions the board must make; agents must stop at the gate and let Paperclip wake them after resolution.

## Employee hierarchy

The Operations Manager may assign tasks but cannot create agents or skills. Research, Production, and QA cannot assign tasks, create agents, or create skills. All employees have `maxConcurrentRuns=1`; the VM-wide scheduler cap is two runs. This allows collaboration without letting a single company exhaust the host.

The four profiles have distinct Hermes homes, workspaces, role skills, session/memory stores, sandbox homes, and Docker reuse identities. They currently use separate copies of the same provisioned provider credential. That is filesystem isolation, not provider-account isolation; use distinct provider credentials if a client requires per-employee provider attribution or revocation.

## Normal operating loop

1. The board or manager creates a scoped issue with owner, expected output, acceptance criteria, and dependencies.
2. Paperclip queues a wake; the global and per-agent caps admit it.
3. Hermes works through its role and tool boundaries and records evidence.
4. Downstream issues release automatically when blockers complete.
5. QA tests independently; the manager integrates findings and makes the release recommendation.
6. The board resolves decisions or approvals. Codex supervises platform health and intervenes only when the control plane needs administration or recovery.

## Failure behavior

Do not steal an active checkout after HTTP 409. Do not mark a blocked issue done to clear the queue. On provider or tool failure, post a concise non-secret diagnostic and name the unblock owner/action. Cancellation and emergency stop are expected, recoverable states; validate that no labeled container or run remains active before resuming.
