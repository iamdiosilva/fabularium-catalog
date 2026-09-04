# Fabularium - Supabase Community V2

This migration is applied **after** the already-running Supabase Foundation V1.

## What V2 adds

- Common user accounts backed by Supabase Auth
- Public community profiles
- Admin/User role recognition using `fabularium_admins`
- Points, reputation, approved-upload and likes-received counters
- Community likes
- Submission lifecycle
- Moderation reviews
- Duplicate candidate analysis
- Pending Telegram metadata fields for the future Worker
- `contributor_id`, `storage_key` and `content_fingerprint` support

Heavy files still stay outside Supabase.

## 1. Apply the SQL migration

Open **Supabase > SQL Editor** and execute the complete file:

`supabase/community_v2.sql`

The migration is designed to run after Foundation V1.

## 2. Existing admin account

V2 automatically creates a profile for Auth users that existed before this migration.
Your existing entry in `fabularium_admins` remains the source of Admin permissions.

You can confirm it with:

```sql
select
  p.user_id,
  p.username,
  p.display_name,
  a.user_id is not null as is_admin
from public.fabularium_profiles p
left join public.fabularium_admins a
  on a.user_id = p.user_id;
```

## 3. Flutter files

Copy the contents of this package over the project root.

V2 does not add a new Dart dependency; `supabase_flutter` is already present from V1.

## 4. Run

```powershell
flutter analyze
flutter run --profile -d windows --dart-define-from-file=config/supabase.local.json
```

## 5. Validation

Open the new account icon in the main catalog AppBar.

Validate:

1. Existing admin can sign in.
2. Admin profile shows the `ADMIN` chip.
3. `Moderation` button opens the moderation queue.
4. Create a second normal account.
5. The second account shows the `USER` chip.
6. Editing username/display name persists after restarting the app.

If **Confirm email** is enabled in Supabase Auth, a newly-created user receives an email and the session remains signed out until confirmation. This is expected.

## Current lifecycle prepared by V2

```text
uploading
  -> uploaded
  -> processing
  -> pending_review
  -> duplicate_suspected (when needed)
  -> approved
  -> publishing
  -> published

or

pending_review
  -> rejected
```

The Worker will later call the service-role-only RPC:

`mark_fabularium_submission_pending_review(...)`

after the file has been stored in the private Telegram Pending channel.

## Next implementation

Community V3 will connect the real Fabularium upload flow:

`User -> Submission -> Worker -> Private Pending Telegram -> Duplicate Analysis -> Admin Review`

Approval will then reuse the existing Telegram documents in the obfuscated official Storage channel without uploading the gigabytes again.
