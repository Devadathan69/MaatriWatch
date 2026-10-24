# Internet deployment

Supabase already hosts PostgreSQL and Firebase handles identity and app push.
The missing component is a public HTTPS API with two continuously running
workers. The Android builds must then use that public API instead of localhost.

## Neysa or another Linux CPU host

Request a small Linux VM with at least 2 CPU cores, 2 GB RAM, outbound HTTPS
and PostgreSQL/TLS access, and a public hostname. A GPU is unnecessary: model
requests go to the configured OpenAI API. Confirm the credit balance, expiry,
spending limit and whether billing can remain disabled after credits expire.

Install Docker Engine with Compose on the host. Point the API hostname at its
public IP. Allow inbound TCP 80/443 for HTTPS and certificate issuance; restrict
administrative SSH access. A managed container host with its own HTTPS endpoint
can run the same image without Caddy.

1. Copy `backend/production.env.example` to `backend/.env.production` **on the
   host** and fill it through the host's private secret mechanism. Restrict its
   file permissions to the deployment owner. Keep the supplied Supabase TLS
   Session pooler URI, Firebase Admin JSON and OpenAI key private. Use a fresh
   random `SECRET_KEY`. Set the exact deployed web origins and a real Firebase
   activation continue page; authorise that page's domain in Firebase Auth.
   The API supplies `/activate`, a static continue page after Firebase's hosted
   handler completes the account action. It does not consume action codes.
   Set `FIREBASE_AUTH_ACTION_URL` to its public HTTPS URL. Set `API_HOST` to the public API
   hostname without a scheme or path. All three demo flags must remain false.
2. Back up the existing Supabase database before schema changes. From the
   repository root, build the image and run the existing migration helper as a
   controlled deployment job (never in each web worker's startup):

   ```sh
   docker compose --env-file backend/.env.production -f deploy/compose.yaml build
   docker compose --env-file backend/.env.production -f deploy/compose.yaml run --rm --no-deps api python scripts/apply_migrations.py
   docker compose --env-file backend/.env.production -f deploy/compose.yaml up -d
   ```

   The current database is already migrated through `014`; the helper detects
   existing schema and reasserts its server-only access policy.
3. Verify `https://API_HOST/healthz` and `/readyz`. The latter must report
   `ready`. An unauthenticated `/api/v1/account/access` must return 401. Check
   that the `api`, `realtime` and `companion` services stay running. The companion
   process delivers guardian SOS and reminders; the realtime process drains
   durable Firebase projections. Stopping a worker must never count as a
   successful deployment.
4. After remote readiness is verified, stop the laptop's recorded API/workers
   during the cutover. Each API/worker process has a pool of one to four database
   sessions; this three-process configuration reserves three and can use twelve.
   Avoid duplicate deployments that exhaust the small Supabase Session pooler.

The image runs as an unprivileged user. The Compose backend has a read-only
filesystem, bounded temporary storage, no added capabilities, restart policies
and a readiness check. Caddy manages HTTPS certificates. The image context uses
an allowlist to exclude environment files, backups, account exports and local
data. Gunicorn access logging is disabled to avoid logging patient identifiers
or URLs containing sensitive query values.

## Managed single-container hosting

Build using `backend/` as the Docker context and `backend/Dockerfile`. Inject
the same production variables using platform secrets. Leave the image's default
command, `python container_entrypoint.py all`. It supervises Gunicorn and both
workers, terminates all children on shutdown, and exits nonzero if a required
process stops so the platform can restart the container. Set the platform health
path to `/readyz`; the web process binds to its injected `PORT`.

Render Free is an internet-testing fallback. Its inactivity sleep also stops
both workers, so timed reminders and SOS delivery have no always-on guarantee.
Do not represent that tier as production availability. Do not add artificial
keep-alive traffic to hide this limitation. Keep persistent records in the
existing Supabase database rather than an ephemeral container filesystem.

## Switch and reinstall the phones

Once the public API is ready, change only `API_BASE_URL` in the ignored
`patient_app/firebase-config.local.json` to `https://API_HOST/api/v1`. Keep the
existing Firebase client settings and demo mode disabled. Rebuild:

```sh
cd patient_app
flutter build apk --debug -t lib/main.dart --dart-define-from-file=firebase-config.local.json --no-pub
```

Install this same build on the two phones one at a time using the single USB
cable. Disconnect them afterward: both can sign in and use the hosted API over
Wi-Fi or mobile data. Existing accounts and Supabase records remain unchanged.
Repeat guardian linking, notification permission and foreground/background SOS
tests against the public deployment.

The debug build is for device testing. A distributable release also requires a
private release signing key and the corresponding Android release configuration;
keep the keystore and its passwords out of Git.
