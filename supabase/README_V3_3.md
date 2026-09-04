# Community V3.3 — Approval → Official Storage

Apply `supabase/community_v3_3.sql`, replace the Dart files, then run:

```powershell
flutter analyze
dart run bin/fabularium_worker.dart --config=config/worker.local.json
```

Expected Worker startup:

```text
Community V3.3 Pending + Official publication processor enabled.
```

Then, in the admin profile:

`Moderation → Approve`

The Worker should log:

```text
Official publication started.
Reading Pending manifest...
Publishing opaque Official Catalog anchor...
Publishing opaque Official Files anchor...
Reusing Pending documents in Official Files group 1...
Reusing Pending manifest in Official Files...
Verifying Official Catalog...
Verifying Official Files...
Official Telegram publication verified.
Official publication verified and committed.
Pending storage removed after publication.
```

The important validation is that approval must NOT print:

```text
Opening 8 Telegram upload connections...
Uploading 1/...
```

because V3.3 reuses the already uploaded Telegram `Document` with
`InputMediaDocument`; it does not upload the GB again.

After success:

- submission = `published`
- a new `fabularium_models` row exists
- a new `fabularium_packages` row exists
- `fabularium_storage_parts` points to Official Files message IDs
- contributor receives +20 points / +5 reputation only after publication
- Pending messages are deleted
- Official Telegram messages contain opaque identifiers/files only

Rejected and confirmed-duplicate submissions are also cleaned from Pending by
the Worker sweep.
