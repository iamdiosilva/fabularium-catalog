# Legacy Screen Cleanup Plan — V3.4.1

The new product flow is:

Fabularium Login
→ Telegram Connection
→ App

The following pages are no longer part of the normal application navigation:

- `lib/pages/download_access_page.dart`
- `lib/pages/telegram_login_page.dart`
- `lib/pages/telegram_group_pages.dart`
- `lib/pages/telegram_storage_page.dart`
- `lib/pages/telegram_catalog_page.dart`

V3.4.1 intentionally does **not** delete those files yet.

Reason: the Local Studio Library still comes from the older administrative
catalog and may still reference legacy Telegram pages internally. Removing files
in the same step as the session rewrite would mix two large refactors and make
regression diagnosis harder.

Recommended cleanup after V3.4.1 validation:

1. Remove Telegram Login and Telegram Catalog actions from the Local Studio
   Library.
2. Search the repository for the five page classes above.
3. Remove any last administrative references.
4. Delete the unused page files.
5. Run `flutter analyze`.
6. Validate Local Studio Library direct publication and Community downloads.

The only Telegram UI intended to remain long-term is:

- the mandatory `TelegramConnectionPage` used by the entry gate;
- `TelegramStorageSettingsPage` for Admin storage configuration.

Telegram remains infrastructure, not a browsing section of Fabularium.
