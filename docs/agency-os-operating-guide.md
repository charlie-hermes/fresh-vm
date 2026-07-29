# Agency OS operating guide

This guide explains how to use the live Hermes, Paperclip, Buzz, and Agency OS
setup in everyday language.

The current system status is **LIVE PRODUCTION**. The exact acceptance evidence
is recorded in the Agency OS repository at `docs/live-production-status.md`.

## What each part does

- Paperclip is the work board. It stores tasks, owners, dependencies, comments,
  approvals, and the permanent work history.
- Hermes runs the 12 specialist roles. Each role has its own files, memory,
  session, permissions, and sandbox.
- Buzz is the private discussion space used during a task. A Buzz decision is
  copied back to Paperclip before it becomes official.
- Agency OS is the workflow and safety layer. It connects the parts and enforces
  brand, approval, publishing, and role boundaries.
- The Agency OS operator page is a read-only summary. Paperclip remains the
  place where you create, assign, approve, or change work.

## The 12 roles

1. Agency Director: breaks a goal into work, assigns it, and brings the result
   together.
2. Technical Implementation Specialist: carries out reviewed technical work.
3. Platform Assurance Reviewer: checks the platform independently and reports
   pass or fail.
4. Brand and Brief Steward: turns your source material into a clear, controlled
   brief.
5. Search and Content Strategist: researches and prepares the content plan.
6. Content Producer: creates the draft.
7. Search and Answer Optimiser: improves search and answer usefulness without
   inventing claims.
8. Visual and Creative Specialist: prepares a visual package and manual creative
   handoff.
9. Editorial Integrity QA: checks claims, sources, policy, accessibility, and
   acceptance rules.
10. Social Amplifier: makes channel-ready versions from an approved Core asset.
11. Publishing Operator: publishes only an exactly approved package to an
    allowed destination.
12. Growth Intelligence Analyst: validates the result, measures what is known,
    and records learning.

Only the Agency Director can assign work to another role. No role can approve
its own work. The Platform Assurance Reviewer reports independently.

## Open the two operator pages

Both pages are private. Open SSH tunnels from your own computer. Replace
`YOUR_VM` with the VM address.

```sh
ssh -L 3100:172.30.0.1:3100 -L 3180:127.0.0.1:3180 ubuntu@YOUR_VM
```

Keep that terminal open. Then use your browser:

- Paperclip: `http://127.0.0.1:3100`
- Agency OS status: `http://127.0.0.1:3180`

Paperclip login details were created during the first install and are stored on
the VM at `/root/paperclip-firstboot-credentials`. View them only in a private
terminal and do not copy them into tasks, chat, source files, or screenshots.

```sh
sudo less /root/paperclip-firstboot-credentials
```

## Check the system before starting work

Run:

```sh
sudo systemctl is-active paperclip.service agency-os-operator.service
systemctl --user is-active buzz-codex-bridge.service
sudo systemctl --failed --no-pager
```

The first two commands should say `active`. The final command should show no
failed units.

For the full production check, go to the reviewed `fresh-vm` checkout and run:

```sh
sudo ./verify.sh
```

The final status must be:

```text
PLATFORM: PASS
FUNCTIONAL ACCEPTANCE: PASS
AGENCY OS: LIVE
SECRET AUDIT: PASS
SYSTEMD FAILED UNITS: 0
PRODUCTION: READY
```

## Start a normal Core campaign

1. Sign in to Paperclip.
2. Open the correct company. Never place two real clients in the same company.
3. Create a parent issue and assign it to the Agency Director.
4. Use a clear title, such as `Create the August balcony garden guide`.
5. In the description, include:
   - the business goal;
   - the audience;
   - the product tier: `search_authority_core` or
     `search_authority_social`;
   - the facts and source material the team may use;
   - prohibited claims;
   - the expected deliverables;
   - the acceptance rules;
   - the target date;
   - the person who can approve publication.
6. Attach or link source material. Do not paste passwords, API keys, private
   keys, or bearer tokens.
7. Set the issue to `todo` when it is ready.
8. Let the Agency Director create and assign the specialist tasks.

A good issue is specific. For example:

```text
Goal: Produce a useful guide for first-time balcony gardeners.
Audience: UK apartment renters with a small balcony.
Product: search_authority_social.
Allowed facts: Use only the attached approved brand facts and cited public sources.
Do not claim: guaranteed results, medical benefits, or legal compliance.
Deliverables: approved article, publication package, social package, and measurement plan.
Approval owner: Human brand owner.
Done when: QA passes, the exact package is approved, and the receipt is checked.
```

## What happens during the Core workflow

1. The Brand and Brief Steward checks the facts, restrictions, and approval
   owner.
2. The Search and Content Strategist prepares the evidence and plan.
3. The Content Producer writes the draft.
4. The Search and Answer Optimiser improves the approved claims and structure.
5. Editorial Integrity QA returns `PASS`, `REVISE`, or `FAIL`.
6. If QA says `REVISE`, the task goes back to the role that owns the problem.
7. When QA passes, the Publishing Operator prepares the exact publication
   package.
8. Paperclip asks a human for approval.
9. After approval, the Publishing Operator sends that exact package to the
   allowed destination and checks the receipt.
10. The Growth Intelligence Analyst records validation, measurements, limits,
    and useful learning.

The production acceptance uses a protected mock destination. It proves the
complete process without posting client material to the public internet.

## Approve or reject work

1. Open the approval request in Paperclip.
2. Open the linked issue and review the QA result.
3. Check the destination, account, asset checksum, public fields, and expiry.
4. Approve only if they exactly match what you intend to release.
5. Reject the request if anything is missing or different. State the reason in
   plain language.
6. Never ask an agent to approve its own output.

Changing the package after approval makes the old approval invalid. Request a
new approval for the changed package.

## Use the Social workflow

Choose `search_authority_social` in the parent issue when social work is wanted.
The Social workflow starts only after the Core asset has:

- final QA `PASS`;
- exact human approval;
- a checked `PUBLISHED` receipt.

The Visual and Creative Specialist prepares the visual handoff. The Social
Amplifier prepares channel-specific copy. Editorial QA checks the exact social
package. A human then approves or rejects it. The Publishing Operator cannot
post a changed or unapproved package.

The system does not automate replies, follows, likes, direct messages, or paid
media.

## Use Buzz correctly

Buzz is for short-lived private collaboration during a Paperclip task. Use it
to discuss a named question, evidence gap, QA correction, or handoff.

Buzz is not the official task board. When the team reaches a decision, the
decision and its Buzz message ID must be written back to the Paperclip issue.
Task state, approval, and completion remain in Paperclip.

Check the bridge with:

```sh
systemctl --user status buzz-codex-bridge.service --no-pager
```

Do not put credentials or raw client secrets in Buzz.

## Read the Agency OS operator page

Open `http://127.0.0.1:3180` through the SSH tunnel. It shows:

- portfolio and brand counts;
- campaigns and stages;
- Paperclip task status;
- approval state;
- the publishing calendar;
- performance and evidence references;
- all 12 installed roles;
- provider connection policy and status.

The page cannot change work. Make changes in Paperclip. The service takes a new
snapshot when it starts. Restart it to refresh the page:

```sh
sudo systemctl restart agency-os-operator.service
```

## Add a second brand

Create a separate Paperclip company for every real brand. Give it a separate
brand ID, Buzz channels, credentials, destinations, and approval owners. Do not
reuse a client company as a folder for another client.

The production test creates a fictional second company and proves that a Social
workflow cannot start from another brand's Core asset. The failed attempt must
create no tasks.

## Provider connections

CMS, analytics, Search Console, SEO data, social, creative, and CRM are listed
as manual handoffs until a real account is connected. `Manual handoff` means a
human completes the provider step and records the result in Paperclip. It does
not mean the provider is connected.

Before changing a provider to connected, supply:

1. the real provider account and destination;
2. a narrowly scoped credential stored outside tasks and source code;
3. a reviewed adapter for the required action;
4. an egress allowlist and cost/rate limits;
5. read-only and sandbox acceptance checks;
6. reconciliation and rollback instructions;
7. exact human approval for the first live write.

Until all seven exist, keep using the manual handoff. Never mark a handoff as a
successful connection simply to clear a task.

## Stop and resume all employees

For an emergency stop:

```sh
sudo /opt/paperclip/ops/paperclip-emergency-control stop
```

Check the state:

```sh
sudo /opt/paperclip/ops/paperclip-emergency-control status
```

Resume only after checking why work was stopped:

```sh
sudo /opt/paperclip/ops/paperclip-emergency-control resume
```

After resuming, inspect every issue that was running or queued. Do not mark an
interrupted issue done unless its evidence and output are present.

## Useful logs and evidence

```sh
sudo journalctl -u paperclip.service -n 200 --no-pager
sudo journalctl -u agency-os-operator.service -n 100 --no-pager
sudo tail -n 20 /var/lib/paperclip/soak/samples.jsonl | jq .
sudo jq . /var/lib/paperclip-appliance/agency-os-production.json
```

The production evidence contains IDs and pass/fail facts, not credential values.
The 12-role functional evidence is at
`/var/lib/paperclip/acceptance-evidence/functional-acceptance.json`.

## If something goes wrong

- A task stays blocked: open its blockers and approval request in Paperclip.
- A role does not run: check whether it is paused and read the Paperclip run log.
- Paperclip is unhealthy: check `paperclip.service`, Docker, disk space, and the
  health URL.
- Buzz does not work: check the user service and do not replace its identity.
- The operator page is stale: restart `agency-os-operator.service`.
- A provider step is unavailable: leave the task blocked or use the documented
  manual handoff. Do not invent success.
- Verification fails: fix the named failure and rerun the same command. Do not
  edit the gate or delete evidence to force a pass.

VM backups and recovery are managed by the human VM owner. They are not an
Agency OS release gate and do not block normal use.
