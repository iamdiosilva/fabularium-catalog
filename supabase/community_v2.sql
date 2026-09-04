-- ============================================================
-- Fabularium - Supabase Community Foundation V2
-- ============================================================
-- Apply AFTER Foundation V1.
--
-- Adds:
--   - common user profiles
--   - Admin/User identity
--   - submissions + moderation
--   - duplicate candidates
--   - likes
--   - points/reputation ledger
--   - contributor/storage fields on models/packages
--
-- Heavy files are NOT stored in Supabase.
-- Telegram remains the binary storage layer.
-- ============================================================

begin;

create extension if not exists pgcrypto;
create extension if not exists pg_trgm;

-- ============================================================
-- 1. COMMUNITY PROFILES
-- ============================================================

create table if not exists public.fabularium_profiles (
  user_id uuid primary key
    references auth.users(id)
    on delete cascade,

  username text not null,
  display_name text not null,
  avatar_url text,
  bio text,

  points bigint not null default 0,
  reputation integer not null default 0,
  approved_uploads integer not null default 0,
  likes_received integer not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists
  fabularium_profiles_username_lower_uidx
on public.fabularium_profiles(lower(username));

create index if not exists
  fabularium_profiles_points_idx
on public.fabularium_profiles(points desc);

create index if not exists
  fabularium_profiles_reputation_idx
on public.fabularium_profiles(reputation desc);

alter table public.fabularium_profiles
  enable row level security;

create or replace function public.handle_new_fabularium_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_requested text;
  v_username text;
  v_display_name text;
  v_suffix text;
begin
  v_requested := lower(
    regexp_replace(
      coalesce(
        nullif(new.raw_user_meta_data->>'username', ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'user'
      ),
      '[^a-zA-Z0-9_]+',
      '_',
      'g'
    )
  );

  v_requested := trim(both '_' from v_requested);

  if char_length(v_requested) < 3 then
    v_requested := 'user';
  end if;

  v_requested := left(v_requested, 24);
  v_username := v_requested;
  v_suffix := left(replace(new.id::text, '-', ''), 6);

  if exists (
    select 1
    from public.fabularium_profiles p
    where lower(p.username) = lower(v_username)
  ) then
    v_username :=
      left(v_requested, 17) || '_' || v_suffix;
  end if;

  v_display_name := coalesce(
    nullif(new.raw_user_meta_data->>'display_name', ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    v_username
  );

  insert into public.fabularium_profiles (
    user_id,
    username,
    display_name
  )
  values (
    new.id,
    v_username,
    v_display_name
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists
  on_auth_user_created_fabularium
on auth.users;

create trigger on_auth_user_created_fabularium
after insert on auth.users
for each row
execute function public.handle_new_fabularium_user();

-- Backfill accounts that already existed before V2.
insert into public.fabularium_profiles (
  user_id,
  username,
  display_name
)
select
  u.id,
  'user_' || left(replace(u.id::text, '-', ''), 8),
  coalesce(
    nullif(u.raw_user_meta_data->>'display_name', ''),
    nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
    'Fabularium User'
  )
from auth.users u
where not exists (
  select 1
  from public.fabularium_profiles p
  where p.user_id = u.id
);

create or replace function public.touch_fabularium_profile_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists
  touch_fabularium_profiles_updated_at
on public.fabularium_profiles;

create trigger touch_fabularium_profiles_updated_at
before update on public.fabularium_profiles
for each row
execute function public.touch_fabularium_profile_updated_at();

-- Public profiles contain no private authentication data.
drop policy if exists
  "Fabularium profiles public read"
on public.fabularium_profiles;

create policy "Fabularium profiles public read"
on public.fabularium_profiles
for select
to anon, authenticated
using (true);

drop policy if exists
  "Fabularium users update own profile"
on public.fabularium_profiles;

create policy "Fabularium users update own profile"
on public.fabularium_profiles
for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

revoke all on public.fabularium_profiles
  from anon, authenticated;

grant select on public.fabularium_profiles
  to anon, authenticated;

-- Users can edit identity/profile fields only. They cannot directly change
-- points, reputation or counters.
grant update (
  username,
  display_name,
  avatar_url,
  bio
) on public.fabularium_profiles
to authenticated;

-- ============================================================
-- 2. MODEL/PACKAGE COMMUNITY FIELDS
-- ============================================================

alter table public.fabularium_models
  add column if not exists contributor_id uuid;

alter table public.fabularium_models
  add column if not exists likes_count integer not null default 0;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fabularium_models_contributor_fk'
  ) then
    alter table public.fabularium_models
      add constraint fabularium_models_contributor_fk
      foreign key (contributor_id)
      references public.fabularium_profiles(user_id)
      on delete set null;
  end if;
end
$$;

alter table public.fabularium_packages
  add column if not exists submitted_by uuid;

alter table public.fabularium_packages
  add column if not exists storage_key text;

alter table public.fabularium_packages
  add column if not exists content_fingerprint text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'fabularium_packages_submitted_by_fk'
  ) then
    alter table public.fabularium_packages
      add constraint fabularium_packages_submitted_by_fk
      foreign key (submitted_by)
      references public.fabularium_profiles(user_id)
      on delete set null;
  end if;
end
$$;

create unique index if not exists
  fabularium_packages_storage_key_uidx
on public.fabularium_packages(storage_key)
where storage_key is not null;

create index if not exists
  fabularium_packages_archive_sha_idx
on public.fabularium_packages(archive_sha256);

create index if not exists
  fabularium_packages_content_fingerprint_idx
on public.fabularium_packages(content_fingerprint)
where content_fingerprint is not null;

-- ============================================================
-- 3. SUBMISSIONS
-- ============================================================

create table if not exists public.fabularium_submissions (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid not null
    references public.fabularium_profiles(user_id)
    on delete restrict,

  name text not null,
  studio text,
  category text,
  model_type text,
  scale text,
  height text,
  description text,
  tags text[] not null default '{}'::text[],

  status text not null default 'uploading'
    check (
      status in (
        'uploading',
        'uploaded',
        'processing',
        'pending_review',
        'duplicate_suspected',
        'approved',
        'publishing',
        'published',
        'rejected',
        'failed'
      )
    ),

  duplicate_status text not null default 'unchecked'
    check (
      duplicate_status in (
        'unchecked',
        'unique',
        'possible',
        'exact',
        'confirmed'
      )
    ),

  duplicate_of_model_id text
    references public.fabularium_models(model_id)
    on delete set null,

  source_folder_name text,
  source_size bigint not null default 0,
  archive_file_name text,
  archive_size bigint not null default 0,
  archive_sha256 text,
  content_fingerprint text,
  storage_key text,

  -- Pending Telegram is PRIVATE and only the Worker/Admin account belongs to it.
  pending_channel_id bigint,
  pending_header_message_id bigint,
  pending_file_message_ids bigint[] not null default '{}'::bigint[],
  pending_manifest_message_id bigint,

  published_model_id text
    references public.fabularium_models(model_id)
    on delete set null,
  published_package_id text
    references public.fabularium_packages(package_id)
    on delete set null,

  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid
    references public.fabularium_profiles(user_id)
    on delete set null,
  review_note text,
  published_at timestamptz
);

create index if not exists
  fabularium_submissions_user_idx
on public.fabularium_submissions(
  submitted_by,
  submitted_at desc
);

create index if not exists
  fabularium_submissions_status_idx
on public.fabularium_submissions(
  status,
  submitted_at
);

create index if not exists
  fabularium_submissions_archive_sha_idx
on public.fabularium_submissions(archive_sha256)
where archive_sha256 is not null;

create index if not exists
  fabularium_submissions_fingerprint_idx
on public.fabularium_submissions(content_fingerprint)
where content_fingerprint is not null;

create unique index if not exists
  fabularium_submissions_storage_key_uidx
on public.fabularium_submissions(storage_key)
where storage_key is not null;

create or replace function public.touch_fabularium_submission_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists
  touch_fabularium_submissions_updated_at
on public.fabularium_submissions;

create trigger touch_fabularium_submissions_updated_at
before update on public.fabularium_submissions
for each row
execute function public.touch_fabularium_submission_updated_at();

alter table public.fabularium_submissions
  enable row level security;

-- Owners see their submissions. Admins see every submission.
drop policy if exists
  "Fabularium submission owner read"
on public.fabularium_submissions;

create policy "Fabularium submission owner read"
on public.fabularium_submissions
for select
to authenticated
using (
  submitted_by = auth.uid()
  or public.is_fabularium_admin()
);

revoke all on public.fabularium_submissions
  from anon, authenticated;

grant select on public.fabularium_submissions
  to authenticated;

-- Client creation goes through create_fabularium_submission().
-- Worker writes use service_role and bypass RLS.

-- ============================================================
-- 4. MODERATION REVIEWS
-- ============================================================

create table if not exists public.fabularium_moderation_reviews (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null
    references public.fabularium_submissions(id)
    on delete cascade,
  reviewed_by uuid not null
    references public.fabularium_profiles(user_id)
    on delete restrict,
  decision text not null
    check (decision in ('approve', 'reject', 'duplicate')),
  note text,
  duplicate_of_model_id text
    references public.fabularium_models(model_id)
    on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists
  fabularium_moderation_reviews_submission_idx
on public.fabularium_moderation_reviews(
  submission_id,
  created_at desc
);

alter table public.fabularium_moderation_reviews
  enable row level security;

drop policy if exists
  "Fabularium moderation review read"
on public.fabularium_moderation_reviews;

create policy "Fabularium moderation review read"
on public.fabularium_moderation_reviews
for select
to authenticated
using (
  public.is_fabularium_admin()
  or exists (
    select 1
    from public.fabularium_submissions s
    where s.id = submission_id
      and s.submitted_by = auth.uid()
  )
);

revoke all on public.fabularium_moderation_reviews
  from anon, authenticated;

grant select on public.fabularium_moderation_reviews
  to authenticated;

-- ============================================================
-- 5. DUPLICATE CANDIDATES
-- ============================================================

create table if not exists public.fabularium_duplicate_candidates (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null
    references public.fabularium_submissions(id)
    on delete cascade,
  model_id text not null
    references public.fabularium_models(model_id)
    on delete cascade,
  match_kind text not null
    check (
      match_kind in (
        'archive_sha256',
        'content_fingerprint',
        'metadata'
      )
    ),
  confidence numeric(5,4) not null default 0,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  unique (submission_id, model_id, match_kind)
);

alter table public.fabularium_duplicate_candidates
  enable row level security;

drop policy if exists
  "Fabularium duplicate candidate read"
on public.fabularium_duplicate_candidates;

create policy "Fabularium duplicate candidate read"
on public.fabularium_duplicate_candidates
for select
to authenticated
using (
  public.is_fabularium_admin()
  or exists (
    select 1
    from public.fabularium_submissions s
    where s.id = submission_id
      and s.submitted_by = auth.uid()
  )
);

revoke all on public.fabularium_duplicate_candidates
  from anon, authenticated;

grant select on public.fabularium_duplicate_candidates
  to authenticated;

-- ============================================================
-- 6. SCORE / REPUTATION LEDGER
-- ============================================================

create table if not exists public.fabularium_score_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null
    references public.fabularium_profiles(user_id)
    on delete cascade,
  event_type text not null,
  source_key text not null unique,
  points_delta integer not null default 0,
  reputation_delta integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists
  fabularium_score_events_user_idx
on public.fabularium_score_events(
  user_id,
  created_at desc
);

alter table public.fabularium_score_events
  enable row level security;

drop policy if exists
  "Fabularium score event own read"
on public.fabularium_score_events;

create policy "Fabularium score event own read"
on public.fabularium_score_events
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_fabularium_admin()
);

revoke all on public.fabularium_score_events
  from anon, authenticated;

grant select on public.fabularium_score_events
  to authenticated;

create or replace function public.apply_fabularium_score_event()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    update public.fabularium_profiles
    set
      points = greatest(0, points + new.points_delta),
      reputation = greatest(0, reputation + new.reputation_delta)
    where user_id = new.user_id;

    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.fabularium_profiles
    set
      points = greatest(0, points - old.points_delta),
      reputation = greatest(0, reputation - old.reputation_delta)
    where user_id = old.user_id;

    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists
  apply_fabularium_score_event_insert
on public.fabularium_score_events;

drop trigger if exists
  apply_fabularium_score_event_delete
on public.fabularium_score_events;

create trigger apply_fabularium_score_event_insert
after insert on public.fabularium_score_events
for each row
execute function public.apply_fabularium_score_event();

create trigger apply_fabularium_score_event_delete
after delete on public.fabularium_score_events
for each row
execute function public.apply_fabularium_score_event();

-- ============================================================
-- 7. LIKES
-- ============================================================

create table if not exists public.fabularium_likes (
  model_id text not null
    references public.fabularium_models(model_id)
    on delete cascade,
  user_id uuid not null
    references public.fabularium_profiles(user_id)
    on delete cascade,
  created_at timestamptz not null default now(),

  primary key (model_id, user_id)
);

create index if not exists
  fabularium_likes_user_idx
on public.fabularium_likes(
  user_id,
  created_at desc
);

alter table public.fabularium_likes
  enable row level security;

drop policy if exists
  "Fabularium likes public read"
on public.fabularium_likes;

create policy "Fabularium likes public read"
on public.fabularium_likes
for select
to anon, authenticated
using (true);

drop policy if exists
  "Fabularium users create own likes"
on public.fabularium_likes;

create policy "Fabularium users create own likes"
on public.fabularium_likes
for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists
  "Fabularium users remove own likes"
on public.fabularium_likes;

create policy "Fabularium users remove own likes"
on public.fabularium_likes
for delete
to authenticated
using (user_id = auth.uid());

revoke all on public.fabularium_likes
  from anon, authenticated;

grant select on public.fabularium_likes
  to anon, authenticated;

grant insert, delete on public.fabularium_likes
  to authenticated;

create or replace function public.handle_fabularium_like_score()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_contributor uuid;
  v_source_key text;
begin
  if tg_op = 'INSERT' then
    update public.fabularium_models
    set likes_count = likes_count + 1
    where model_id = new.model_id;

    select contributor_id
    into v_contributor
    from public.fabularium_models
    where model_id = new.model_id;

    if v_contributor is not null
       and v_contributor <> new.user_id then
      update public.fabularium_profiles
      set likes_received = likes_received + 1
      where user_id = v_contributor;

      v_source_key :=
        'like:' || new.model_id || ':' || new.user_id::text;

      insert into public.fabularium_score_events (
        user_id,
        event_type,
        source_key,
        points_delta,
        reputation_delta
      )
      values (
        v_contributor,
        'like_received',
        v_source_key,
        2,
        0
      )
      on conflict (source_key) do nothing;
    end if;

    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.fabularium_models
    set likes_count = greatest(0, likes_count - 1)
    where model_id = old.model_id;

    v_source_key :=
      'like:' || old.model_id || ':' || old.user_id::text;

    delete from public.fabularium_score_events
    where source_key = v_source_key
    returning user_id into v_contributor;

    if v_contributor is not null
       and v_contributor <> old.user_id then
      update public.fabularium_profiles
      set likes_received = greatest(0, likes_received - 1)
      where user_id = v_contributor;
    end if;

    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists
  handle_fabularium_like_insert
on public.fabularium_likes;

drop trigger if exists
  handle_fabularium_like_delete
on public.fabularium_likes;

create trigger handle_fabularium_like_insert
after insert on public.fabularium_likes
for each row
execute function public.handle_fabularium_like_score();

create trigger handle_fabularium_like_delete
after delete on public.fabularium_likes
for each row
execute function public.handle_fabularium_like_score();

-- ============================================================
-- 8. SAFE CLIENT RPC: CREATE SUBMISSION
-- ============================================================

create or replace function public.create_fabularium_submission(
  payload jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_id uuid;
  v_name text := nullif(trim(payload->>'name'), '');
begin
  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if v_name is null then
    raise exception 'Submission name is required';
  end if;

  insert into public.fabularium_submissions (
    submitted_by,
    name,
    studio,
    category,
    model_type,
    scale,
    height,
    description,
    tags,
    source_folder_name,
    source_size,
    archive_file_name,
    archive_size,
    archive_sha256,
    content_fingerprint,
    storage_key,
    status
  )
  values (
    v_user_id,
    v_name,
    nullif(trim(payload->>'studio'), ''),
    nullif(trim(payload->>'category'), ''),
    nullif(trim(payload->>'type'), ''),
    nullif(trim(payload->>'scale'), ''),
    nullif(trim(payload->>'height'), ''),
    nullif(payload->>'description', ''),
    coalesce(
      array(
        select jsonb_array_elements_text(
          coalesce(payload->'tags', '[]'::jsonb)
        )
      ),
      '{}'::text[]
    ),
    nullif(payload->>'sourceFolderName', ''),
    coalesce(nullif(payload->>'sourceSize', '')::bigint, 0),
    nullif(payload->>'archiveFileName', ''),
    coalesce(nullif(payload->>'archiveSize', '')::bigint, 0),
    nullif(payload->>'archiveSha256', ''),
    nullif(payload->>'contentFingerprint', ''),
    nullif(payload->>'storageKey', ''),
    'uploading'
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function
  public.create_fabularium_submission(jsonb)
from public;

grant execute on function
  public.create_fabularium_submission(jsonb)
to authenticated;

-- ============================================================
-- 9. DUPLICATE ANALYSIS
-- ============================================================

create or replace function public.analyze_fabularium_submission(
  target_submission_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_submission public.fabularium_submissions%rowtype;
  v_has_exact boolean := false;
  v_has_possible boolean := false;
begin
  select *
  into v_submission
  from public.fabularium_submissions
  where id = target_submission_id;

  if not found then
    raise exception 'Submission not found';
  end if;

  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if v_submission.submitted_by <> auth.uid()
     and not public.is_fabularium_admin() then
    raise exception 'Access denied';
  end if;

  delete from public.fabularium_duplicate_candidates
  where submission_id = target_submission_id;

  if nullif(v_submission.archive_sha256, '') is not null then
    insert into public.fabularium_duplicate_candidates (
      submission_id,
      model_id,
      match_kind,
      confidence,
      details
    )
    select distinct
      target_submission_id,
      p.model_id,
      'archive_sha256',
      1,
      jsonb_build_object(
        'packageId', p.package_id,
        'archiveSha256', p.archive_sha256
      )
    from public.fabularium_packages p
    where p.archive_sha256 = v_submission.archive_sha256
      and p.status = 'published'
      and p.deleted_at is null
    on conflict (submission_id, model_id, match_kind)
      do update set
        confidence = excluded.confidence,
        details = excluded.details;
  end if;

  if nullif(v_submission.content_fingerprint, '') is not null then
    insert into public.fabularium_duplicate_candidates (
      submission_id,
      model_id,
      match_kind,
      confidence,
      details
    )
    select distinct
      target_submission_id,
      p.model_id,
      'content_fingerprint',
      1,
      jsonb_build_object(
        'packageId', p.package_id,
        'contentFingerprint', p.content_fingerprint
      )
    from public.fabularium_packages p
    where p.content_fingerprint = v_submission.content_fingerprint
      and p.status = 'published'
      and p.deleted_at is null
    on conflict (submission_id, model_id, match_kind)
      do update set
        confidence = excluded.confidence,
        details = excluded.details;
  end if;

  insert into public.fabularium_duplicate_candidates (
    submission_id,
    model_id,
    match_kind,
    confidence,
    details
  )
  select
    target_submission_id,
    m.model_id,
    'metadata',
    least(
      1,
      similarity(lower(m.name), lower(v_submission.name))
      + case
          when v_submission.studio is not null
           and m.studio is not null
           and lower(m.studio) = lower(v_submission.studio)
          then 0.08
          else 0
        end
    ),
    jsonb_build_object(
      'name', m.name,
      'studio', m.studio,
      'nameSimilarity',
        similarity(lower(m.name), lower(v_submission.name))
    )
  from public.fabularium_models m
  where m.deleted_at is null
    and similarity(
      lower(m.name),
      lower(v_submission.name)
    ) >= 0.72
  on conflict (submission_id, model_id, match_kind)
    do update set
      confidence = excluded.confidence,
      details = excluded.details;

  select exists (
    select 1
    from public.fabularium_duplicate_candidates c
    where c.submission_id = target_submission_id
      and c.match_kind in (
        'archive_sha256',
        'content_fingerprint'
      )
  )
  into v_has_exact;

  select exists (
    select 1
    from public.fabularium_duplicate_candidates c
    where c.submission_id = target_submission_id
      and c.confidence >= 0.72
  )
  into v_has_possible;

  update public.fabularium_submissions
  set
    duplicate_status = case
      when v_has_exact then 'exact'
      when v_has_possible then 'possible'
      else 'unique'
    end,
    status = case
      when v_has_exact or v_has_possible
        then 'duplicate_suspected'
      when status in (
        'uploaded',
        'processing',
        'pending_review',
        'duplicate_suspected'
      ) then 'pending_review'
      else status
    end
  where id = target_submission_id;
end;
$$;

revoke all on function
  public.analyze_fabularium_submission(uuid)
from public;

grant execute on function
  public.analyze_fabularium_submission(uuid)
to authenticated;

-- ============================================================
-- 10. ADMIN MODERATION RPC
-- ============================================================

create or replace function public.review_fabularium_submission(
  target_submission_id uuid,
  decision text,
  note text default null,
  duplicate_of text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_submission public.fabularium_submissions%rowtype;
  v_admin uuid := auth.uid();
  v_decision text := lower(trim(decision));
begin
  if not public.is_fabularium_admin() then
    raise exception 'Fabularium admin access required';
  end if;

  select *
  into v_submission
  from public.fabularium_submissions
  where id = target_submission_id
  for update;

  if not found then
    raise exception 'Submission not found';
  end if;

  if v_submission.status not in (
    'pending_review',
    'duplicate_suspected'
  ) then
    raise exception
      'Submission is not waiting for moderation (current status: %)',
      v_submission.status;
  end if;

  if v_decision = 'approve' then
    update public.fabularium_submissions
    set
      status = 'approved',
      reviewed_at = now(),
      reviewed_by = v_admin,
      review_note = nullif(note, ''),
      duplicate_of_model_id = null
    where id = target_submission_id;

    insert into public.fabularium_moderation_reviews (
      submission_id,
      reviewed_by,
      decision,
      note
    )
    values (
      target_submission_id,
      v_admin,
      'approve',
      nullif(note, '')
    );

    insert into public.fabularium_score_events (
      user_id,
      event_type,
      source_key,
      points_delta,
      reputation_delta
    )
    values (
      v_submission.submitted_by,
      'submission_approved',
      'submission-approved:' || target_submission_id::text,
      20,
      5
    )
    on conflict (source_key) do nothing;

    update public.fabularium_profiles
    set approved_uploads = approved_uploads + 1
    where user_id = v_submission.submitted_by;

    return;
  end if;

  if v_decision = 'reject' then
    update public.fabularium_submissions
    set
      status = 'rejected',
      reviewed_at = now(),
      reviewed_by = v_admin,
      review_note = nullif(note, '')
    where id = target_submission_id;

    insert into public.fabularium_moderation_reviews (
      submission_id,
      reviewed_by,
      decision,
      note
    )
    values (
      target_submission_id,
      v_admin,
      'reject',
      nullif(note, '')
    );

    return;
  end if;

  if v_decision = 'duplicate' then
    if nullif(trim(duplicate_of), '') is null then
      raise exception 'duplicate_of modelId is required';
    end if;

    if not exists (
      select 1
      from public.fabularium_models m
      where m.model_id = duplicate_of
        and m.deleted_at is null
    ) then
      raise exception 'Duplicate target model does not exist';
    end if;

    update public.fabularium_submissions
    set
      status = 'rejected',
      duplicate_status = 'confirmed',
      duplicate_of_model_id = duplicate_of,
      reviewed_at = now(),
      reviewed_by = v_admin,
      review_note = nullif(note, '')
    where id = target_submission_id;

    insert into public.fabularium_moderation_reviews (
      submission_id,
      reviewed_by,
      decision,
      note,
      duplicate_of_model_id
    )
    values (
      target_submission_id,
      v_admin,
      'duplicate',
      nullif(note, ''),
      duplicate_of
    );

    return;
  end if;

  raise exception 'Unsupported moderation decision: %', decision;
end;
$$;

revoke all on function
  public.review_fabularium_submission(uuid, text, text, text)
from public;

grant execute on function
  public.review_fabularium_submission(uuid, text, text, text)
to authenticated;

-- ============================================================
-- 11. WORKER RPC: PENDING TELEGRAM UPLOAD COMPLETE
-- ============================================================
-- Only the future server-side Worker/service_role may call this function.
-- Users never receive the Pending Telegram channel identity.
-- ============================================================

create or replace function public.mark_fabularium_submission_pending_review(
  target_submission_id uuid,
  telegram_channel_id bigint,
  header_message_id bigint,
  file_message_ids bigint[],
  manifest_message_id bigint,
  archive_sha text,
  fingerprint text,
  storage_key_value text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.fabularium_submissions
  set
    pending_channel_id = telegram_channel_id,
    pending_header_message_id = header_message_id,
    pending_file_message_ids = coalesce(
      file_message_ids,
      '{}'::bigint[]
    ),
    pending_manifest_message_id = manifest_message_id,
    archive_sha256 = coalesce(
      nullif(archive_sha, ''),
      archive_sha256
    ),
    content_fingerprint = coalesce(
      nullif(fingerprint, ''),
      content_fingerprint
    ),
    storage_key = coalesce(
      nullif(storage_key_value, ''),
      storage_key
    ),
    status = 'pending_review'
  where id = target_submission_id
    and status in (
      'uploading',
      'uploaded',
      'processing',
      'failed'
    );

  if not found then
    raise exception 'Submission not found or cannot enter review';
  end if;
end;
$$;

revoke all on function
  public.mark_fabularium_submission_pending_review(
    uuid,
    bigint,
    bigint,
    bigint[],
    bigint,
    text,
    text,
    text
  )
from public, anon, authenticated;

grant execute on function
  public.mark_fabularium_submission_pending_review(
    uuid,
    bigint,
    bigint,
    bigint[],
    bigint,
    text,
    text,
    text
  )
to service_role;

-- ============================================================
-- 12. DATA API GRANTS FOR SERVICE ROLE
-- ============================================================

grant all on public.fabularium_profiles
  to service_role;
grant all on public.fabularium_submissions
  to service_role;
grant all on public.fabularium_moderation_reviews
  to service_role;
grant all on public.fabularium_duplicate_candidates
  to service_role;
grant all on public.fabularium_score_events
  to service_role;
grant all on public.fabularium_likes
  to service_role;

commit;
