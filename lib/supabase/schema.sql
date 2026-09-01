-- ============================================================
-- Fabularium Catalog - Supabase Foundation V1
-- ============================================================
--
-- Responsibilities:
--   Supabase: catalog/index/relationships/search metadata
--   Telegram: original gallery, archives, split parts, manifest backup
--
-- model_id   = permanent model identity from config.json
-- package_id = one concrete Telegram storage version/upload
--
-- Run this file once in Supabase SQL Editor.
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- Admin authorization
-- ------------------------------------------------------------

create table if not exists public.fabularium_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.fabularium_admins enable row level security;

create or replace function public.is_fabularium_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.fabularium_admins a
    where a.user_id = auth.uid()
  );
$$;

revoke all on function public.is_fabularium_admin() from public;
grant execute on function public.is_fabularium_admin() to authenticated;

-- ------------------------------------------------------------
-- Models
-- ------------------------------------------------------------

create table if not exists public.fabularium_models (
  model_id text primary key,

  name text not null,
  studio text,
  category text,
  model_type text,
  scale text,
  height text,
  description text,
  tags text[] not null default '{}'::text[],

  active_package_id text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists fabularium_models_name_idx
  on public.fabularium_models using btree (lower(name));

create index if not exists fabularium_models_studio_idx
  on public.fabularium_models using btree (lower(studio));

create index if not exists fabularium_models_category_idx
  on public.fabularium_models using btree (lower(category));

create index if not exists fabularium_models_tags_gin_idx
  on public.fabularium_models using gin (tags);

-- ------------------------------------------------------------
-- Storage packages
-- ------------------------------------------------------------

create table if not exists public.fabularium_packages (
  package_id text primary key,
  model_id text not null
    references public.fabularium_models(model_id)
    on delete cascade,

  status text not null default 'published'
    check (status in ('published', 'deleted')),

  source_folder_name text not null,
  source_size bigint not null default 0,

  archive_file_name text not null,
  archive_size bigint not null default 0,
  archive_sha256 text not null,
  part_count integer not null default 0,

  telegram_catalog_channel_id bigint not null,
  telegram_catalog_channel_title text,
  telegram_gallery_grouped_id bigint,

  telegram_files_channel_id bigint not null,
  telegram_files_channel_title text,
  telegram_files_header_message_id bigint,
  telegram_manifest_message_id bigint,

  manifest_json jsonb not null default '{}'::jsonb,

  package_created_at timestamptz,
  published_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists fabularium_packages_model_idx
  on public.fabularium_packages(model_id);

create index if not exists fabularium_packages_published_idx
  on public.fabularium_packages(published_at desc);

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fabularium_models_active_package_fk'
  ) then
    alter table public.fabularium_models
      add constraint fabularium_models_active_package_fk
      foreign key (active_package_id)
      references public.fabularium_packages(package_id)
      on delete set null
      deferrable initially deferred;
  end if;
end
$$;

-- ------------------------------------------------------------
-- Gallery
-- ------------------------------------------------------------

create table if not exists public.fabularium_gallery_items (
  package_id text not null
    references public.fabularium_packages(package_id)
    on delete cascade,

  position integer not null,
  telegram_message_id bigint not null,
  telegram_grouped_id bigint,
  file_name text,

  -- Future V2: small thumbnail stored in Supabase Storage/CDN.
  thumbnail_path text,

  created_at timestamptz not null default now(),

  primary key (package_id, position),
  unique (package_id, telegram_message_id)
);

create index if not exists fabularium_gallery_package_idx
  on public.fabularium_gallery_items(package_id, position);

-- ------------------------------------------------------------
-- File groups
-- ------------------------------------------------------------

create table if not exists public.fabularium_file_groups (
  package_id text not null
    references public.fabularium_packages(package_id)
    on delete cascade,

  group_index integer not null,
  telegram_grouped_id bigint,
  created_at timestamptz not null default now(),

  primary key (package_id, group_index)
);

-- ------------------------------------------------------------
-- Storage parts
-- ------------------------------------------------------------

create table if not exists public.fabularium_storage_parts (
  package_id text not null
    references public.fabularium_packages(package_id)
    on delete cascade,

  part_index integer not null,
  group_index integer not null,

  file_name text not null,
  size bigint not null,
  sha256 text not null,
  telegram_message_id bigint not null,

  created_at timestamptz not null default now(),

  primary key (package_id, part_index),

  constraint fabularium_storage_parts_group_fk
    foreign key (package_id, group_index)
    references public.fabularium_file_groups(package_id, group_index)
    on delete cascade
);

create index if not exists fabularium_storage_parts_package_idx
  on public.fabularium_storage_parts(package_id, part_index);

-- ------------------------------------------------------------
-- updated_at trigger
-- ------------------------------------------------------------

create or replace function public.touch_fabularium_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_fabularium_models_updated_at
  on public.fabularium_models;

create trigger touch_fabularium_models_updated_at
before update on public.fabularium_models
for each row
execute function public.touch_fabularium_updated_at();

drop trigger if exists touch_fabularium_packages_updated_at
  on public.fabularium_packages;

create trigger touch_fabularium_packages_updated_at
before update on public.fabularium_packages
for each row
execute function public.touch_fabularium_updated_at();

-- ------------------------------------------------------------
-- Transactional package publication RPC
-- ------------------------------------------------------------
--
-- Flutter sends one JSON object. PostgreSQL performs the entire publication
-- atomically, so the remote catalog never sees half a package.
--
-- Expected top-level keys:
-- modelId, packageId, model, package, telegram, gallery, fileGroups, parts,
-- manifest
-- ------------------------------------------------------------

create or replace function public.publish_fabularium_package(
  payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_model_id text := nullif(trim(payload->>'modelId'), '');
  v_package_id text := nullif(trim(payload->>'packageId'), '');
begin
  if not public.is_fabularium_admin() then
    raise exception 'Fabularium admin access required';
  end if;

  if v_model_id is null then
    raise exception 'modelId is required';
  end if;

  if v_package_id is null then
    raise exception 'packageId is required';
  end if;

  insert into public.fabularium_models (
    model_id,
    name,
    studio,
    category,
    model_type,
    scale,
    height,
    description,
    tags,
    deleted_at
  )
  values (
    v_model_id,
    coalesce(nullif(trim(payload->'model'->>'name'), ''), 'Unnamed model'),
    nullif(trim(payload->'model'->>'studio'), ''),
    nullif(trim(payload->'model'->>'category'), ''),
    nullif(trim(payload->'model'->>'type'), ''),
    nullif(trim(payload->'model'->>'scale'), ''),
    nullif(trim(payload->'model'->>'height'), ''),
    nullif(payload->'model'->>'description', ''),
    coalesce(
      array(
        select jsonb_array_elements_text(
          coalesce(payload->'model'->'tags', '[]'::jsonb)
        )
      ),
      '{}'::text[]
    ),
    null
  )
  on conflict (model_id) do update
  set
    name = excluded.name,
    studio = excluded.studio,
    category = excluded.category,
    model_type = excluded.model_type,
    scale = excluded.scale,
    height = excluded.height,
    description = excluded.description,
    tags = excluded.tags,
    deleted_at = null;

  insert into public.fabularium_packages (
    package_id,
    model_id,
    status,
    source_folder_name,
    source_size,
    archive_file_name,
    archive_size,
    archive_sha256,
    part_count,
    telegram_catalog_channel_id,
    telegram_catalog_channel_title,
    telegram_gallery_grouped_id,
    telegram_files_channel_id,
    telegram_files_channel_title,
    telegram_files_header_message_id,
    telegram_manifest_message_id,
    manifest_json,
    package_created_at,
    published_at,
    deleted_at
  )
  values (
    v_package_id,
    v_model_id,
    'published',
    coalesce(payload->'package'->>'sourceFolderName', ''),
    coalesce((payload->'package'->>'sourceSize')::bigint, 0),
    coalesce(payload->'package'->>'archiveFileName', ''),
    coalesce((payload->'package'->>'archiveSize')::bigint, 0),
    coalesce(payload->'package'->>'archiveSha256', ''),
    coalesce((payload->'package'->>'partCount')::integer, 0),
    (payload->'telegram'->'catalog'->>'channelId')::bigint,
    nullif(payload->'telegram'->'catalog'->>'channelTitle', ''),
    nullif(payload->'telegram'->'catalog'->>'galleryGroupedId', '')::bigint,
    (payload->'telegram'->'files'->>'channelId')::bigint,
    nullif(payload->'telegram'->'files'->>'channelTitle', ''),
    nullif(payload->'telegram'->'files'->>'headerMessageId', '')::bigint,
    nullif(payload->'telegram'->'files'->>'manifestMessageId', '')::bigint,
    coalesce(payload->'manifest', '{}'::jsonb),
    nullif(payload->'package'->>'createdAt', '')::timestamptz,
    now(),
    null
  )
  on conflict (package_id) do update
  set
    model_id = excluded.model_id,
    status = 'published',
    source_folder_name = excluded.source_folder_name,
    source_size = excluded.source_size,
    archive_file_name = excluded.archive_file_name,
    archive_size = excluded.archive_size,
    archive_sha256 = excluded.archive_sha256,
    part_count = excluded.part_count,
    telegram_catalog_channel_id = excluded.telegram_catalog_channel_id,
    telegram_catalog_channel_title = excluded.telegram_catalog_channel_title,
    telegram_gallery_grouped_id = excluded.telegram_gallery_grouped_id,
    telegram_files_channel_id = excluded.telegram_files_channel_id,
    telegram_files_channel_title = excluded.telegram_files_channel_title,
    telegram_files_header_message_id =
      excluded.telegram_files_header_message_id,
    telegram_manifest_message_id =
      excluded.telegram_manifest_message_id,
    manifest_json = excluded.manifest_json,
    package_created_at = excluded.package_created_at,
    published_at = now(),
    deleted_at = null;

  delete from public.fabularium_gallery_items
  where package_id = v_package_id;

  insert into public.fabularium_gallery_items (
    package_id,
    position,
    telegram_message_id,
    telegram_grouped_id,
    file_name,
    thumbnail_path
  )
  select
    v_package_id,
    coalesce((item->>'position')::integer, ordinality::integer - 1),
    (item->>'messageId')::bigint,
    nullif(item->>'groupedId', '')::bigint,
    nullif(item->>'fileName', ''),
    nullif(item->>'thumbnailPath', '')
  from jsonb_array_elements(
    coalesce(payload->'gallery', '[]'::jsonb)
  ) with ordinality as gallery(item, ordinality);

  delete from public.fabularium_storage_parts
  where package_id = v_package_id;

  delete from public.fabularium_file_groups
  where package_id = v_package_id;

  insert into public.fabularium_file_groups (
    package_id,
    group_index,
    telegram_grouped_id
  )
  select
    v_package_id,
    (item->>'groupIndex')::integer,
    nullif(item->>'groupedId', '')::bigint
  from jsonb_array_elements(
    coalesce(payload->'fileGroups', '[]'::jsonb)
  ) as groups(item);

  insert into public.fabularium_storage_parts (
    package_id,
    part_index,
    group_index,
    file_name,
    size,
    sha256,
    telegram_message_id
  )
  select
    v_package_id,
    (item->>'partIndex')::integer,
    (item->>'groupIndex')::integer,
    coalesce(item->>'fileName', ''),
    coalesce((item->>'size')::bigint, 0),
    coalesce(item->>'sha256', ''),
    (item->>'messageId')::bigint
  from jsonb_array_elements(
    coalesce(payload->'parts', '[]'::jsonb)
  ) as parts(item);

  update public.fabularium_models
  set
    active_package_id = v_package_id,
    deleted_at = null
  where model_id = v_model_id;
end;
$$;

revoke all on function public.publish_fabularium_package(jsonb) from public;
grant execute on function public.publish_fabularium_package(jsonb)
  to authenticated;

-- ------------------------------------------------------------
-- Soft delete RPC
-- ------------------------------------------------------------

create or replace function public.delete_fabularium_package(
  target_package_id text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_model_id text;
begin
  if not public.is_fabularium_admin() then
    raise exception 'Fabularium admin access required';
  end if;

  select model_id
  into v_model_id
  from public.fabularium_packages
  where package_id = target_package_id;

  if v_model_id is null then
    return;
  end if;

  update public.fabularium_packages
  set
    status = 'deleted',
    deleted_at = now()
  where package_id = target_package_id;

  update public.fabularium_models
  set
    active_package_id = null
  where model_id = v_model_id
    and active_package_id = target_package_id;
end;
$$;

revoke all on function public.delete_fabularium_package(text) from public;
grant execute on function public.delete_fabularium_package(text)
  to authenticated;

-- ------------------------------------------------------------
-- Row Level Security
-- ------------------------------------------------------------

alter table public.fabularium_models enable row level security;
alter table public.fabularium_packages enable row level security;
alter table public.fabularium_gallery_items enable row level security;
alter table public.fabularium_file_groups enable row level security;
alter table public.fabularium_storage_parts enable row level security;

drop policy if exists "Fabularium public models read"
  on public.fabularium_models;

create policy "Fabularium public models read"
on public.fabularium_models
for select
to anon, authenticated
using (deleted_at is null);

drop policy if exists "Fabularium public packages read"
  on public.fabularium_packages;

create policy "Fabularium public packages read"
on public.fabularium_packages
for select
to anon, authenticated
using (
  status = 'published'
  and deleted_at is null
);

drop policy if exists "Fabularium public gallery read"
  on public.fabularium_gallery_items;

create policy "Fabularium public gallery read"
on public.fabularium_gallery_items
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.fabularium_packages p
    where p.package_id = fabularium_gallery_items.package_id
      and p.status = 'published'
      and p.deleted_at is null
  )
);

drop policy if exists "Fabularium public file groups read"
  on public.fabularium_file_groups;

create policy "Fabularium public file groups read"
on public.fabularium_file_groups
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.fabularium_packages p
    where p.package_id = fabularium_file_groups.package_id
      and p.status = 'published'
      and p.deleted_at is null
  )
);

drop policy if exists "Fabularium public storage parts read"
  on public.fabularium_storage_parts;

create policy "Fabularium public storage parts read"
on public.fabularium_storage_parts
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.fabularium_packages p
    where p.package_id = fabularium_storage_parts.package_id
      and p.status = 'published'
      and p.deleted_at is null
  )
);

-- Direct table writes are admin-only. Package publication should normally use
-- publish_fabularium_package() so all related rows are updated atomically.

drop policy if exists "Fabularium admin models write"
  on public.fabularium_models;

create policy "Fabularium admin models write"
on public.fabularium_models
for all
to authenticated
using (public.is_fabularium_admin())
with check (public.is_fabularium_admin());

drop policy if exists "Fabularium admin packages write"
  on public.fabularium_packages;

create policy "Fabularium admin packages write"
on public.fabularium_packages
for all
to authenticated
using (public.is_fabularium_admin())
with check (public.is_fabularium_admin());

drop policy if exists "Fabularium admin gallery write"
  on public.fabularium_gallery_items;

create policy "Fabularium admin gallery write"
on public.fabularium_gallery_items
for all
to authenticated
using (public.is_fabularium_admin())
with check (public.is_fabularium_admin());

drop policy if exists "Fabularium admin file groups write"
  on public.fabularium_file_groups;

create policy "Fabularium admin file groups write"
on public.fabularium_file_groups
for all
to authenticated
using (public.is_fabularium_admin())
with check (public.is_fabularium_admin());

drop policy if exists "Fabularium admin storage parts write"
  on public.fabularium_storage_parts;

create policy "Fabularium admin storage parts write"
on public.fabularium_storage_parts
for all
to authenticated
using (public.is_fabularium_admin())
with check (public.is_fabularium_admin());

-- Explicit Data API grants. RLS still controls which rows are visible/writable.
grant select on public.fabularium_models
  to anon, authenticated;
grant select on public.fabularium_packages
  to anon, authenticated;
grant select on public.fabularium_gallery_items
  to anon, authenticated;
grant select on public.fabularium_file_groups
  to anon, authenticated;
grant select on public.fabularium_storage_parts
  to anon, authenticated;

grant insert, update, delete on public.fabularium_models
  to authenticated;
grant insert, update, delete on public.fabularium_packages
  to authenticated;
grant insert, update, delete on public.fabularium_gallery_items
  to authenticated;
grant insert, update, delete on public.fabularium_file_groups
  to authenticated;
grant insert, update, delete on public.fabularium_storage_parts
  to authenticated;

-- Admin table: no anonymous visibility.
grant select on public.fabularium_admins to authenticated;

drop policy if exists "Fabularium admins can read self"
  on public.fabularium_admins;

create policy "Fabularium admins can read self"
on public.fabularium_admins
for select
to authenticated
using (user_id = auth.uid());

commit;
