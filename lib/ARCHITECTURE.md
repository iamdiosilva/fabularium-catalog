# Fabularium `lib/` architecture

This refactor uses a feature-first Clean Architecture migration.

- `features/*/domain`: pure state/entities and repository contracts.
- `features/*/application`: orchestration/use cases/controllers.
- `features/*/data`: adapters that bridge the domain to filesystem/Telegram.
- `features/*/presentation`: Flutter pages and widgets.
- `services`: existing low-level infrastructure. The MTProto/download/upload code
  stays here intentionally because it is already validated and is being migrated
  behind feature adapters incrementally.
- `pages`, `models`, `widgets`: compatibility entry points for existing imports.

The active Catalog and Telegram Storage Recovery flows now depend on interfaces
at the feature boundary rather than reaching directly into UI-owned state.
