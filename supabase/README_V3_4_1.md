# Fabularium V3.4.1 — Unified Login Flow

## New startup flow

```text
Start Fabularium
      ↓
Fabularium session exists?
      │
      ├─ NO → Fabularium Login
      │
      └─ YES
             ↓
      Telegram session valid?
             │
             ├─ NO → Telegram Connection
             │
             └─ YES
                    ↓
                 APP
```

Telegram is currently mandatory because community downloads are a core app
capability and Admin storage operations also depend on Telegram.

`FabulariumSessionService.telegramRequired` centralizes that product decision so
a future browse-only mode can relax it without redesigning the login screens.

## Logout

Account → Sign Out now performs:

1. reset in-memory download session state;
2. delete Telegram saved session;
3. sign out from Supabase/Fabularium;
4. return to the first route.

The next app session must complete the full flow again.

## UI cleanup

Removed from the main navigation:

- separate Download Access management;
- Legacy Telegram Tools;
- Legacy Telegram Catalog.

Community model detail no longer contains fallback login navigation. The entry
gate guarantees both sessions before users can access the catalog.

See:

`docs/legacy_screen_cleanup_v3_4_1.md`

for the next physical file-deletion pass.

## Files

- `lib/main.dart`
- `lib/services/fabularium_session_service.dart`
- `lib/pages/fabularium_entry_gate.dart`
- `lib/pages/fabularium_login_page.dart`
- `lib/pages/telegram_connection_page.dart`
- `lib/pages/fabularium_shell_page.dart`
- `lib/features/community/presentation/pages/community_account_page.dart`
- `lib/features/community/presentation/pages/community_catalog_detail_page.dart`

No Supabase migration is required for V3.4.1.

## Test

```powershell
flutter analyze
flutter run --profile -d windows --dart-define-from-file=config/supabase.local.json
```

### Case A — both sessions already valid

App should restore both and enter Explore.

### Case B — Fabularium valid, Telegram missing

App should go directly to Telegram Connection.

### Case C — no Fabularium session

App should show Fabularium Login first. After successful login, Telegram
Connection must appear before Explore.

### Case D — logout

Account → Manage Account → Sign Out.

After confirmation, both sessions must be removed and Fabularium Login must
appear. A subsequent login must require Telegram again.
