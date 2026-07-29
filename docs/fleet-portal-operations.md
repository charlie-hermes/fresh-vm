# Fleet G2.6 portal operations

## What is installed

G2.6 runs four separate services:

- `fleet-portal-web.service` is the unprivileged Next.js portal on
  `127.0.0.1:3190`. It has no Paperclip credential and no authority database
  access.
- `fleet-portal-authority.service` owns protected portal membership, session,
  command and catalogue data and accepts only the portal process over a local
  Unix socket.
- `fleet-portal-command-worker.service` is the only portal component that can
  deliver a restricted decision to Paperclip.
- `fleet-ingest-worker.service` scans and extracts uploads without network
  access. Its output always requires review.

Paperclip remains private at `172.30.0.1:3100`. The client portal must be
reached through Cloudflare Access and a Cloudflare Tunnel to the loopback web
service. Do not publish port 3190 directly.

## Required external setup

Create these in WorkOS:

1. a production AuthKit application;
2. the exact redirect URI
   `https://fleet.madebyfleet.com/auth/callback`;
3. one WorkOS organisation for the Fleet DMA customer account; and
4. the initial Fleet owner user in that organisation.

Create these in Cloudflare Zero Trust:

1. a client Access application for `fleet.madebyfleet.com`;
2. a separate Fleet-only Access application for `admin.madebyfleet.com`;
3. an Access audience for the portal;
4. a Tunnel route from both hosts to `http://127.0.0.1:3190`; and
5. policies that deny access unless the expected identity is present.

The client and administrator policies must remain separate even while Fleet
DMA is the only production tenant.

## Configure secrets without putting them in the shell history

Create a root-readable file outside Git with exactly these keys and real
values:

```text
WORKOS_CLIENT_ID=client_replace
WORKOS_API_KEY=sk_replace
WORKOS_COOKIE_PASSWORD=replace_with_at_least_32_random_characters
NEXT_PUBLIC_WORKOS_REDIRECT_URI=https://fleet.madebyfleet.com/auth/callback
FLEET_WORKOS_ORGANIZATION_ID=org_replace
FLEET_OWNER_WORKOS_SUBJECT=user_replace
CLOUDFLARE_ACCESS_TEAM_DOMAIN=replace.cloudflareaccess.com
CLOUDFLARE_ACCESS_AUDIENCE=replace
FLEET_PORTAL_ADMIN_USER_IDS=user_replace
```

If a real, still-pending Paperclip approval is ready to display, the file may
also contain both `FLEET_PORTAL_ACTIVE_APPROVAL_ID` and
`FLEET_PORTAL_ACTIVE_APPROVAL_CHECKSUM`. The checksum must come from the
reviewed read projection; it is not invented by the portal.

Then run:

```bash
sudo fleet-portal-configure /absolute/secure/path/fleet-portal.env
```

The command validates the file, saves only the service configuration with mode
`0600`, admits the Fleet DMA owner, materialises the one honest controlled
content item and starts the four services. It never prints a secret.

## Cloudflare health and exposure

The local check is:

```bash
curl --fail --silent http://127.0.0.1:3190/health | jq
```

Expected authority is `fleet_portal`. Also confirm the VM listens only on
loopback:

```bash
sudo ss -ltnp | grep ':3190'
```

After the Tunnel is configured, visit `https://fleet.madebyfleet.com`. A user
must pass Cloudflare Access and WorkOS and must match the stored organisation,
membership and exact hostname.

## Safe rollback

To stop writes while preserving all evidence:

```bash
sudo fleet-portal-mutations disable
```

For a full portal rollback, disable the Cloudflare route and stop the portal
and worker services. Do not delete `/var/lib/agency-os/fleet-portal.sqlite3` or
the ingest evidence directories.

After the cause is resolved and reviewed, restore writes with
`sudo fleet-portal-mutations enable`.
