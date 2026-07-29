# Agency OS role activation

## Scope and provenance

This release activates all 12 Agency OS roles, the Core and optional Social
workflows, the read-only operator portal, and controlled provider handoffs.
Real provider accounts remain manual until the owner supplies them.

The role contracts were copied byte-for-byte from `agency-os` merge commit
`43da2e9a4df4cd957fa8cf2f2b7ec0ac70124d6f`. The authoritative per-file hashes
are in `files/factory/core-roles.tsv`; repository, installed-asset, profile,
Paperclip managed-bundle, and fresh-process Hermes checks all bind to those
hashes.

| Role ID | Paperclip role | Reports to | Runtime authority |
|---|---|---|---|
| `agency-director` | `ceo` | board | may assign Core tasks; cannot create agents/skills or self-approve |
| `technical-implementation-specialist` | `devops` | Agency Director | implements reviewed technical work; cannot deploy itself |
| `platform-assurance-reviewer` | `qa` | board | independently verifies the platform; cannot modify or self-approve |
| `brand-brief-steward` | `pm` | Agency Director | brief/evidence stewardship only |
| `search-content-strategist` | `researcher` | Agency Director | approved public search and strategy |
| `content-producer` | `designer` | Agency Director | sandboxed content production |
| `search-answer-optimiser` | `researcher` | Agency Director | sandboxed search/answer optimisation |
| `editorial-integrity-qa` | `qa` | Agency Director | independent review; no production authority |
| `visual-creative-specialist` | `designer` | Agency Director | prepares visual packages through controlled manual handoff |
| `publishing-operator` | `devops` | Agency Director | sandbox publication/reconciliation only |
| `social-amplifier` | `pm` | Agency Director | creates approved social adaptations; no autonomous posting |
| `growth-intelligence-analyst` | `researcher` | Agency Director | approved observation and analysis |

Every Agency OS employee uses Paperclip's protected assignment policy. All
specialists have no assignment grant, `canAssignTasks=false`,
`canCreateAgents=false`, and `canCreateSkills=false`; the Agency Director alone
has the explicit assignment grant represented by `canAssignTasks=true`. Every
role has `maxConcurrentRuns=1`; the appliance admits at most two Hermes runs
across the VM.

## Existing-appliance activation

Activation is a reviewed release operation, not normal employee work.

1. Confirm no Paperclip heartbeat run is queued/running and no Hermes container
   is running.
2. From the exact reviewed checkout, run:

   ```sh
   sudo ./scripts/core-role-transition activate
   ```

3. The command verifies the current platform, records the existing identity
   map, installs the locked release, creates or updates all 12 profiles while
   paused, verifies credentials, changes the active identity map, starts the
   operator portal, resumes the roles, and resets every runtime session.
4. Reboot only if another configuration change requires it. Run:

   ```sh
   sudo ./verify.sh
   ```

`core-role-transition` restores the prior identity map, employee states, and
transition status after `ERR`, `HUP`, `INT`, or `TERM` at every recoverable
cutover checkpoint. `SIGKILL` cannot be trapped; after a killed transition,
wait for all runs and containers to stop, then rerun the same `activate` or
`rollback` command. Re-running `activate` against an active Agency OS runtime
first verifies the installed platform and validates the current credential
copies without replacing them from the retained
legacy profiles. It then snapshots the current Core Paperclip configuration,
permissions, managed instructions, status, identity map, and managed profile
files before arming the distinct `reconcile` recovery mode and making any live
employee mutation. A recoverable
failure restores that snapshot, the Core identity map, and the prior transition
status; a later retry also restores a snapshot left by `SIGKILL` before retrying.

Do not report activation complete until all five release lines pass.

## What acceptance proves

`runtime-bundle-verify` starts a new pinned Hermes Python process for every
profile. It proves:

- `SOUL.md` is loaded exactly from that role's unique `HERMES_HOME`;
- `AGENTS.md` is loaded exactly from that role's actual working directory;
- Paperclip's managed `AGENTS.md` bytes match the same checksum;
- each registry-denied toolset is absent from the profile configuration;
- no bundle is blocked or substituted by Hermes context discovery.

Functional acceptance then resets all 12 Paperclip runtime sessions and
assigns all 12 employees real, role-specific acceptance issues. Every role
must complete one allowed action from a deterministic fixture, explicitly
refuse its nearest denied action, leave the prohibited artifact absent, create
and read a mutually exclusive workspace sentinel inside its Docker identity,
confirm Docker sockets are absent, and return an attributed Paperclip comment.
The Strategist must also produce successful web-search tool-completion evidence
from the host-owned Hermes agent log, bound to the session identifier retained
in that Paperclip run log.
The Director must create exactly one scoped backlog child assigned to the Brief
Steward. The Steward must attempt the inverse assignment through a URL carrying
a unique per-run probe token; host-owned Paperclip service journal evidence must
show that exact POST returned 403, and the Steward issue must have zero children
of any title. Together these prove the Director's explicit grant and the
specialist denial against protected Core targets without trusting agent-authored
claims. Host inspection validates the allowed artifacts,
denied side effects, the pre/post checksum of every immutable input and sentinel,
every mount, and that the global scheduler ran exactly two concurrently while
queueing the remainder. The retained evidence records `allowedAction`,
`deniedAction`, `allowedActionPass`, `deniedRefusalPass`, `noSideEffectPass`,
`inputIntegrityPass`, `denialTracePass`, `assignmentPolicyPass`, and
`roleBoundaryPass` for every role.

This activates the runtime identities and their bounded local capabilities. It
also runs the approved fictional Core and Social workflows through authenticated
Paperclip and private Buzz. Real client publication still needs a connected
provider and a new exact human approval.

## Rollback

With zero live runs and zero Hermes containers:

```sh
sudo /usr/local/sbin/paperclip-core-role-transition rollback
```

The command pauses all Core roles, restores the legacy identity map, and resumes
the legacy employees. New profiles are retained for investigation. Deploy the
prior reviewed appliance commit immediately afterward; the current verifier
intentionally will not certify a rolled-back four-role runtime as the current
12-role release.
