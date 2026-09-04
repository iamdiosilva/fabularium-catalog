# Fabularium Community V3.4

V3.4 changes the product center from the old local/Telegram admin catalog to the
Fabularium Community.

## New desktop flow

Main application:

- Explore
- Contribute
- Downloads
- Account
- Studio Tools (Admin only)

Normal users no longer need to find a separate Telegram page.

Telegram authentication is presented as **Download Access** and is requested
contextually on the first download.

## Community Catalog

The new Supabase-backed catalog supports:

- published models only
- search
- category filter
- studio filter
- pagination
- contributor
- likes
- archive size
- model detail
- direct download

V3.4 does not yet have community cover/gallery uploads, so published community
cards use a neutral model placeholder. Gallery/media is a good V3.5 target.

## Direct download architecture

1. User signs into Fabularium.
2. User clicks Download.
3. If Download Access is not configured, Fabularium opens the guided connection.
4. Supabase returns an authenticated download ticket.
5. The ticket contains the random public Official Files username and exact
   published part message IDs.
6. The user's own Telegram session resolves the public username, obtaining an
   account-correct access hash.
7. Exact document messages are loaded by ID.
8. Parts are added to the existing Fabularium Download Queue.
9. After all parts complete, Fabularium concatenates them in order and verifies
   the original archive SHA-256.
10. A friendly archive named after the model is created in the same folder.

The opaque part files remain in place in V3.4 because the existing Download Queue
still references them. Package-aware queue cleanup can be added later.

## Storage endpoint routing

V3.4 creates `fabularium_storage_endpoints`.

The table is not directly readable by normal clients.

When an Admin opens the new shell, Fabularium reads the locally configured
Official Catalog/Files workspace and automatically synchronizes the public
random usernames to Supabase.

There is also a manual **Sync Routing** button under Studio Tools.

## Installation

1. Extract the ZIP at repository root.
2. Run `supabase/community_v3_4.sql` in Supabase SQL Editor.
3. Run:

```powershell
flutter pub get
flutter analyze
```

4. Start the app:

```powershell
flutter run --profile -d windows --dart-define-from-file=config/supabase.local.json
```

5. Sign in with the Admin account once.

Open:

`Studio Tools -> Community Download Routing`

It should report that routing is synchronized.

## First validation

Explore should show the model published in V3.3.

Open it and test:

- Like
- Download

On the first Download, the new Download Access flow should appear if Telegram
has not yet been authenticated on that Windows profile.

After connection, the part is placed in the existing download queue and the
final archive is SHA-256 verified.
