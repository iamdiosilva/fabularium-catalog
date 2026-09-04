-- ============================================================
-- Fabularium Community V3.4
-- Community Catalog + Direct Download Routing
-- Apply AFTER community_v3_3.sql.
-- ============================================================

begin;

create table if not exists public.fabularium_storage_endpoints (
  role text primary key
    check (role in ('catalog', 'files')),
  channel_id bigint not null,
  public_username text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.fabularium_storage_endpoints
  enable row level security;

revoke all on public.fabularium_storage_endpoints
from anon, authenticated;

grant all on public.fabularium_storage_endpoints
to service_role;

create or replace function public.admin_sync_fabularium_storage_endpoints(
  catalog_channel_id bigint,
  catalog_username text,
  files_channel_id bigint,
  files_username text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_catalog_username text :=
    trim(both '@' from trim(coalesce(catalog_username, '')));
  v_files_username text :=
    trim(both '@' from trim(coalesce(files_username, '')));
begin
  if not public.is_fabularium_admin() then
    raise exception 'Fabularium admin access required';
  end if;

  if catalog_channel_id is null or catalog_channel_id <= 0 then
    raise exception 'Catalog channel ID is invalid';
  end if;

  if files_channel_id is null or files_channel_id <= 0 then
    raise exception 'Files channel ID is invalid';
  end if;

  if v_catalog_username = '' then
    raise exception 'Catalog public username is required';
  end if;

  if v_files_username = '' then
    raise exception 'Files public username is required';
  end if;

  insert into public.fabularium_storage_endpoints (
    role,
    channel_id,
    public_username,
    updated_at,
    updated_by
  )
  values (
    'catalog',
    catalog_channel_id,
    v_catalog_username,
    now(),
    auth.uid()
  )
  on conflict (role) do update
  set
    channel_id = excluded.channel_id,
    public_username = excluded.public_username,
    updated_at = now(),
    updated_by = auth.uid();

  insert into public.fabularium_storage_endpoints (
    role,
    channel_id,
    public_username,
    updated_at,
    updated_by
  )
  values (
    'files',
    files_channel_id,
    v_files_username,
    now(),
    auth.uid()
  )
  on conflict (role) do update
  set
    channel_id = excluded.channel_id,
    public_username = excluded.public_username,
    updated_at = now(),
    updated_by = auth.uid();
end;
$$;

revoke all on function
  public.admin_sync_fabularium_storage_endpoints(
    bigint,
    text,
    bigint,
    text
  )
from public, anon;

grant execute on function
  public.admin_sync_fabularium_storage_endpoints(
    bigint,
    text,
    bigint,
    text
  )
to authenticated;

create or replace function public.browse_fabularium_catalog(
  search_text text default null,
  category_filter text default null,
  studio_filter text default null,
  page_limit integer default 24,
  page_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_search text :=
    nullif(lower(trim(coalesce(search_text, ''))), '');
  v_category text :=
    nullif(lower(trim(coalesce(category_filter, ''))), '');
  v_studio text :=
    nullif(lower(trim(coalesce(studio_filter, ''))), '');
  v_limit integer :=
    greatest(1, least(coalesce(page_limit, 24), 60));
  v_offset integer :=
    greatest(0, coalesce(page_offset, 0));
  v_total integer := 0;
  v_items jsonb := '[]'::jsonb;
begin
  select count(*)
  into v_total
  from public.fabularium_models m
  join public.fabularium_packages p
    on p.package_id = m.active_package_id
  where m.deleted_at is null
    and p.deleted_at is null
    and p.status = 'published'
    and (
      v_category is null
      or lower(coalesce(m.category, '')) = v_category
    )
    and (
      v_studio is null
      or lower(coalesce(m.studio, '')) = v_studio
    )
    and (
      v_search is null
      or lower(m.name) like '%' || v_search || '%'
      or lower(coalesce(m.studio, '')) like '%' || v_search || '%'
      or lower(coalesce(m.category, '')) like '%' || v_search || '%'
      or lower(coalesce(m.model_type, '')) like '%' || v_search || '%'
      or exists (
        select 1
        from unnest(coalesce(m.tags, '{}'::text[])) as tag(value)
        where lower(tag.value) like '%' || v_search || '%'
      )
    );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'modelId', q.model_id,
        'packageId', q.package_id,
        'name', q.name,
        'studio', q.studio,
        'category', q.category,
        'type', q.model_type,
        'scale', q.scale,
        'height', q.height,
        'description', q.description,
        'tags', to_jsonb(q.tags),
        'contributorId', q.contributor_id,
        'contributorUsername', q.username,
        'contributorDisplayName', q.display_name,
        'contributorAvatarUrl', q.avatar_url,
        'likeCount', q.like_count,
        'archiveSize', q.archive_size,
        'partCount', q.part_count,
        'publishedAt', q.published_at
      )
      order by q.published_at desc, lower(q.name)
    ),
    '[]'::jsonb
  )
  into v_items
  from (
    select
      m.model_id,
      p.package_id,
      m.name,
      m.studio,
      m.category,
      m.model_type,
      m.scale,
      m.height,
      m.description,
      m.tags,
      m.contributor_id,
      profile.username,
      profile.display_name,
      profile.avatar_url,
      (
        select count(*)
        from public.fabularium_likes likes
        where likes.model_id = m.model_id
      )::integer as like_count,
      p.archive_size,
      p.part_count,
      p.published_at
    from public.fabularium_models m
    join public.fabularium_packages p
      on p.package_id = m.active_package_id
    left join public.fabularium_profiles profile
      on profile.user_id = m.contributor_id
    where m.deleted_at is null
      and p.deleted_at is null
      and p.status = 'published'
      and (
        v_category is null
        or lower(coalesce(m.category, '')) = v_category
      )
      and (
        v_studio is null
        or lower(coalesce(m.studio, '')) = v_studio
      )
      and (
        v_search is null
        or lower(m.name) like '%' || v_search || '%'
        or lower(coalesce(m.studio, '')) like '%' || v_search || '%'
        or lower(coalesce(m.category, '')) like '%' || v_search || '%'
        or lower(coalesce(m.model_type, '')) like '%' || v_search || '%'
        or exists (
          select 1
          from unnest(coalesce(m.tags, '{}'::text[])) as tag(value)
          where lower(tag.value) like '%' || v_search || '%'
        )
      )
    order by p.published_at desc, lower(m.name)
    limit v_limit
    offset v_offset
  ) q;

  return jsonb_build_object(
    'total', v_total,
    'items', v_items
  );
end;
$$;

revoke all on function
  public.browse_fabularium_catalog(
    text,
    text,
    text,
    integer,
    integer
  )
from public;

grant execute on function
  public.browse_fabularium_catalog(
    text,
    text,
    text,
    integer,
    integer
  )
to anon, authenticated;

create or replace function public.get_fabularium_catalog_filters()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_categories jsonb;
  v_studios jsonb;
begin
  select coalesce(
    jsonb_agg(value order by lower(value)),
    '[]'::jsonb
  )
  into v_categories
  from (
    select distinct trim(m.category) as value
    from public.fabularium_models m
    join public.fabularium_packages p
      on p.package_id = m.active_package_id
    where m.deleted_at is null
      and p.deleted_at is null
      and p.status = 'published'
      and nullif(trim(coalesce(m.category, '')), '') is not null
  ) categories;

  select coalesce(
    jsonb_agg(value order by lower(value)),
    '[]'::jsonb
  )
  into v_studios
  from (
    select distinct trim(m.studio) as value
    from public.fabularium_models m
    join public.fabularium_packages p
      on p.package_id = m.active_package_id
    where m.deleted_at is null
      and p.deleted_at is null
      and p.status = 'published'
      and nullif(trim(coalesce(m.studio, '')), '') is not null
  ) studios;

  return jsonb_build_object(
    'categories', v_categories,
    'studios', v_studios
  );
end;
$$;

revoke all on function
  public.get_fabularium_catalog_filters()
from public;

grant execute on function
  public.get_fabularium_catalog_filters()
to anon, authenticated;

create or replace function public.get_fabularium_download_ticket(
  target_model_id text
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_package public.fabularium_packages%rowtype;
  v_username text;
  v_parts jsonb;
  v_extension text;
begin
  if auth.uid() is null then
    raise exception 'Fabularium authentication required';
  end if;

  select p.*
  into v_package
  from public.fabularium_models m
  join public.fabularium_packages p
    on p.package_id = m.active_package_id
  where m.model_id = target_model_id
    and m.deleted_at is null
    and p.deleted_at is null
    and p.status = 'published';

  if not found then
    raise exception 'Published model not found';
  end if;

  select endpoint.public_username
  into v_username
  from public.fabularium_storage_endpoints endpoint
  where endpoint.role = 'files';

  if nullif(trim(coalesce(v_username, '')), '') is null then
    raise exception 'Official download routing is not configured';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'partIndex', part.part_index,
        'messageId', part.telegram_message_id,
        'size', part.size,
        'sha256', part.sha256
      )
      order by part.part_index
    ),
    '[]'::jsonb
  )
  into v_parts
  from public.fabularium_storage_parts part
  where part.package_id = v_package.package_id;

  if jsonb_array_length(v_parts) = 0 then
    raise exception 'Published package contains no downloadable parts';
  end if;

  v_extension := lower(
    coalesce(
      v_package.manifest_json->'archive'->>'ext',
      'bin'
    )
  );

  if v_extension !~ '^[a-z0-9]{1,12}$' then
    v_extension := 'bin';
  end if;

  return jsonb_build_object(
    'modelId', target_model_id,
    'packageId', v_package.package_id,
    'filesUsername', v_username,
    'archiveExtension', v_extension,
    'archiveSha256', v_package.archive_sha256,
    'archiveSize', v_package.archive_size,
    'parts', v_parts
  );
end;
$$;

revoke all on function
  public.get_fabularium_download_ticket(text)
from public, anon;

grant execute on function
  public.get_fabularium_download_ticket(text)
to authenticated;

commit;
