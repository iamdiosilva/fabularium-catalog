# Fabularium Community V3.2 — Telegram Pending Pipeline

This stage upgrades the validated V3.1 flow:

User → Worker staging → Supabase `uploaded`

into:

User
→ Worker staging
→ SHA-256
→ content fingerprint
→ opaque storageKey
→ 1 GB parts
→ Telegram Pending PRIVATE
→ exact message verification
→ Supabase Pending metadata
→ duplicate analysis
→ `pending_review` / `duplicate_suspected`
→ delete Worker staging

## Important security change

V3.2 revokes full-table SELECT access to `fabularium_submissions` for normal
authenticated users and grants only safe columns.

The app no longer receives:

- `pending_channel_id`
- `pending_header_message_id`
- `pending_file_message_ids`
- `pending_manifest_message_id`
- `storage_key`

These remain Worker/service-role internals.

## Files in this patch

- `pubspec.yaml`
- `bin/fabularium_worker.dart`
- `lib/services/community_pending_storage_service.dart`
- `lib/features/community/data/community_repository.dart`
- `supabase/community_v3_2.sql`

## 1. Replace files

Extract the ZIP at the repository root.

## 2. Run packages

```powershell
flutter pub get
```

`crypto` is now used for streaming SHA-256.

## 3. Apply SQL migration

Run in Supabase SQL Editor:

`supabase/community_v3_2.sql`

It must be applied after V2 and V3.1.

## 4. Telegram requirements for the local V3.2 test

The Worker currently uses the same local Telegram runtime configuration already
created by Fabularium on your Windows account:

- `%LOCALAPPDATA%\Fabularium\Telegram\telegram_auth.json`
- `%LOCALAPPDATA%\Fabularium\Telegram\storage_workspace.json`

Therefore, before starting the Worker:

1. Telegram must already be authenticated in Fabularium.
2. Catalog and Files may be public.
3. Pending must be configured and PRIVATE.
4. 7-Zip must be installed.

When we move the Worker to the VPS we will bootstrap a dedicated Worker Telegram
account/session there. Normal Fabularium users will never receive this session.

## 5. Start Worker

```powershell
dart run bin/fabularium_worker.dart --config=config/worker.local.json
```

Expected startup includes:

```text
[Fabularium Worker] Community V3.2 Pending processor enabled.
```

The Worker scans every 15 seconds for `uploaded` or interrupted `processing`
submissions. This also provides basic restart recovery.

## 6. Test with a small archive first

Fabularium:

Account
→ My Submissions
→ New Submission
→ select ZIP/RAR/7Z
→ Submit Archive

Expected Worker stages:

```text
Processing started.
Calculating archive SHA-256...
Calculating content fingerprint...
Preparing opaque Telegram parts...
Publishing Pending anchor...
Uploading Pending group 1...
Uploading opaque Pending manifest...
Verifying Pending messages...
Telegram Pending verified.
Duplicate analysis completed.
Pending upload verified and staging released.
```

Expected Telegram Pending:

```text
<32-char storageKey>

<storageKey>.part001
[more parts if needed]

<storageKey>.m1
```

No human model name is used in the Pending Telegram filenames.

## 7. Expected Supabase status

If no duplicate candidate is found:

`pending_review`

If SHA/fingerprint/metadata finds a likely match:

`duplicate_suspected`

The Worker staging directory is deleted only after Telegram verification and
Supabase registration succeed.

## Fingerprint

The archive SHA-256 detects byte-identical uploads.

The content fingerprint is independent of compression settings as much as
possible: the Worker uses 7-Zip to inspect the archive and hashes a canonical,
sorted list of:

`normalized path | uncompressed size | CRC`

This allows the same files re-packed into another ZIP/RAR/7Z to be detected.

## Recovery

A local `.pending_upload.json` journal is written during Telegram publication.
If the upload fails or the Worker restarts and retries, previously published
partial Pending messages are removed before another attempt.

## Next: V3.3

V3.3 is the approval pipeline:

Admin Approve
→ reuse Pending Telegram Documents with `InputMediaDocument`
→ Official public obfuscated Files
→ publish Catalog/gallery metadata
→ verify Official
→ write Supabase package/model
→ delete Pending messages
→ award contributor points/reputation
