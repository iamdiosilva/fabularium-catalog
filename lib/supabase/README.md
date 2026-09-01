# Fabularium Supabase Foundation V1

This layer indexes the Telegram Storage V7.1 catalog. Telegram remains the
source of the heavy files; Supabase becomes the fast relational catalog.

## 1. Create a Supabase project

Create a new project in Supabase.

## 2. Create the schema

Open **SQL Editor** in the Supabase dashboard and run the complete file:

`supabase/schema.sql`

It creates:

- `fabularium_models`
- `fabularium_packages`
- `fabularium_gallery_items`
- `fabularium_file_groups`
- `fabularium_storage_parts`
- `fabularium_admins`
- `publish_fabularium_package(payload jsonb)` RPC
- `delete_fabularium_package(target_package_id text)` RPC
- Row Level Security policies

## 3. Create the Fabularium admin user

In Supabase Authentication, create the account that will publish models.

Then, in SQL Editor, inspect the user id:

```sql
select id, email
from auth.users
order by created_at desc;
```

Register that user as a Fabularium administrator:

```sql
insert into public.fabularium_admins (user_id)
values ('YOUR_AUTH_USER_UUID')
on conflict (user_id) do nothing;
```

For a private/personal catalog, disable public user sign-up in the Supabase
Authentication settings. Do not put a `service_role` or secret key in the
Flutter app.

## 4. Configure Flutter locally

Copy:

`config/supabase.local.example.json`

to:

`config/supabase.local.json`

Fill in the Project URL and the **publishable key** from Supabase.

The local file is ignored by Git.

## 5. Run

```powershell
flutter pub get

flutter run --profile -d windows --dart-define-from-file=config/supabase.local.json
```

Without this local config the application still starts normally; Supabase is
simply disabled.

## Next step

After this foundation is validated, add:

1. Supabase admin sign-in inside Fabularium.
2. `TelegramStoragePackage -> publish_fabularium_package()` mapping.
3. A local Supabase sync status independent from Telegram `STORED`.
4. Telegram Catalog repository backed by Supabase.
5. Supabase Storage thumbnails for fast catalog cards.
