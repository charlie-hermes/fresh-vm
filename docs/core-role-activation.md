# Agency Core role activation

## Scope and provenance

This release activates only the eight Agency Core roles. It does not activate
Social Amplifier roles, real publishing/analytics providers, a full operator
portal, or additional control-plane features.

The role contracts were copied byte-for-byte from `agency-os` merge commit
`d3eb353747323cc3f6a9a0622698737700693c94`. The authoritative per-file hashes
are in `files/factory/core-roles.tsv`; repository, installed-asset, profile,
Paperclip managed-bundle, and fresh-process Hermes checks all bind to those
hashes.

| Role ID | Paperclip role | Reports to | Runtime authority |
|---|---|---|---|
| `agency-director` | `ceo` | board | may assign Core tasks; cannot create agents/skills or self-approve |
| `brand-brief-steward` | `pm` | Agency Director | brief/evidence stewardship only |
| `search-content-strategist` | `researcher` | Agency Director | approved public search and strategy |
| `content-producer` | `designer` | Agency Director | sandboxed content production |
| `search-answer-optimiser` | `researcher` | Agency Director | sandboxed search/answer optimisation |
| `editorial-integrity-qa` | `qa` | Agency Director | independent review; no production authority |
| `publishing-operator` | `devops` | Agency Director | sandbox publication/reconciliation only |
| `growth-intelligence-analyst` | `researcher` | Agency Director | approved observation and analysis |

All specialists have `canAssignTasks=false`, `canCreateAgents=false`, and
`canCreateSkills=false`. The Agency Director has only `canAssignTasks=true`.
Every role has `maxConcurrentRuns=1`; the appliance admits at most two Hermes
runs across the VM.

## Existing-appliance activation

Activation is a reviewed release operation, not normal employee work.

1. Confirm no Paperclip heartbeat run is queued/running and no Hermes container
   is running.
2. From the exact reviewed checkout, run:

   ```sh
   sudo ./scripts/core-role-transition activate
   ```

3. The command verifies the previous platform, creates an encrypted backup,
   records the legacy four-role identity map, installs the locked release,
   creates/updates the eight profiles and employees while paused, copies the
   already-provisioned credential only after all four legacy copies are proven
   identical, pauses the legacy employees, installs the new identity map,
   resumes the Core roles, and resets every runtime session.
4. Reboot only if another configuration change requires it. Run:

   ```sh
   sudo ./verify.sh
   ```

Do not report activation complete until all six release lines pass.

## What acceptance proves

`runtime-bundle-verify` starts a new pinned Hermes Python process for every
profile. It proves:

- `SOUL.md` is loaded exactly from that role's unique `HERMES_HOME`;
- `AGENTS.md` is loaded exactly from that role's actual working directory;
- Paperclip's managed `AGENTS.md` bytes match the same checksum;
- each registry-denied toolset is absent from the profile configuration;
- no bundle is blocked or substituted by Hermes context discovery.

Functional acceptance then resets all eight Paperclip runtime sessions and
assigns all eight employees real acceptance issues. Every role must create and
read a mutually exclusive workspace sentinel inside its Docker identity,
confirm Docker sockets are absent, and return an attributed Paperclip comment.
The two approved research roles must also produce successful web-search tool
completion evidence. Host inspection verifies every mount and records that the
global scheduler ran exactly two concurrently while queueing the remainder.

This activates the runtime identities and their bounded local capabilities. It
does not grant or claim real-client integrations, live publication authority,
Social Amplifier operation, or capabilities deferred by the Agency OS delivery
rebaseline.

## Rollback

With zero live runs and zero Hermes containers:

```sh
sudo /usr/local/sbin/paperclip-core-role-transition rollback
```

The command makes another encrypted backup, pauses all Core roles, restores the
legacy identity map, and resumes the legacy employees. New profiles are
retained for investigation and recovery. Deploy the prior reviewed appliance
commit immediately afterward; the current verifier intentionally will not
certify a rolled-back four-role runtime as the current eight-role release.
