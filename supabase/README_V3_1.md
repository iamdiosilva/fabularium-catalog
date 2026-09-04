# Fabularium Community V3.1 - Submission Intake

This stage validates the path:

Fabularium User
→ Supabase Submission
→ authenticated raw archive upload
→ Fabularium Worker
→ worker local staging
→ Supabase status `uploaded`

It intentionally stops BEFORE Telegram Pending. Telegram processing is V3.2.

## 1. Apply SQL

Run:

`supabase/community_v3_1.sql`

in Supabase SQL Editor after Community V2.

## 2. Create Worker config

Copy:

`config/worker.local.example.json`

to:

`config/worker.local.json`

Fill:

- SUPABASE_URL
- SUPABASE_PUBLISHABLE_KEY
- SUPABASE_SECRET_KEY

Never place `SUPABASE_SECRET_KEY` in the Flutter app or commit it. The Worker also accepts the legacy `SUPABASE_SERVICE_ROLE_KEY` if needed.

For local testing, keep:

- host: 127.0.0.1
- port: 8787

## 3. Start the Worker

In a second terminal:

```powershell
dart run bin/fabularium_worker.dart --config=config/worker.local.json
```

Health check in a browser:

`http://127.0.0.1:8787/health`

Expected JSON contains `"ok":true`.

## 4. Start Flutter

Your current local Supabase config can optionally add:

```json
{
  "SUPABASE_URL": "...",
  "SUPABASE_PUBLISHABLE_KEY": "...",
  "FABULARIUM_WORKER_URL": "http://127.0.0.1:8787"
}
```

Then:

```powershell
flutter run --profile -d windows --dart-define-from-file=config/supabase.local.json
```

## 5. Test

Account
→ My Submissions
→ New Submission
→ select a small ZIP first
→ fill name
→ Submit Archive

Expected:

- app upload reaches 100%
- Worker stores the archive under its data directory
- submission changes from `uploading` to `uploaded`
- `fabularium_upload_jobs` shows `received`

## Security

The Flutter app sends the user's Supabase access token.

The Worker validates it against Supabase Auth and verifies that the submission
belongs to that user.

Only the Worker owns the Supabase service-role key.

Remote Worker URLs are required to use HTTPS. Plain HTTP is accepted only for
localhost development.

## Next: V3.2

V3.2 will process the staged archive:

- SHA-256
- content fingerprint
- 1 GB split
- opaque `storageKey`
- Telegram Pending PRIVATE upload
- manifest
- duplicate analysis
- status `pending_review`
