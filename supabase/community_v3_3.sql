-- Fabularium Community V3.3
-- Apply after community_v3_2.sql.

begin;

alter table public.fabularium_submissions
  add column if not exists publication_error text;

alter table public.fabularium_submissions
  add column if not exists publication_started_at timestamptz;

alter table public.fabularium_packages
  add column if not exists telegram_catalog_access_hash bigint;

alter table public.fabularium_packages
  add column if not exists telegram_catalog_anchor_message_id bigint;

alter table public.fabularium_packages
  add column if not exists telegram_files_access_hash bigint;

-- Approval now queues publication. Points are awarded only after Official
-- Telegram publication succeeds.
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
      duplicate_of_model_id = null,
      publication_error = null
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

    return;
  end if;

  if v_decision = 'reject' then
    update public.fabularium_submissions
    set
      status = 'rejected',
      reviewed_at = now(),
      reviewed_by = v_admin,
      review_note = nullif(note, ''),
      publication_error = null
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
      review_note = nullif(note, ''),
      publication_error = null
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

create or replace function public.worker_begin_fabularium_publication(
  target_submission_id uuid,
  worker_identifier text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;

  update public.fabularium_submissions
  set
    status = 'publishing',
    publication_started_at = now(),
    publication_error = null
  where id = target_submission_id
    and status in ('approved', 'publishing');

  if not found then
    raise exception 'Submission cannot be published';
  end if;
end;
$$;

revoke all on function
  public.worker_begin_fabularium_publication(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.worker_begin_fabularium_publication(uuid, text)
to service_role;

create or replace function public.worker_fail_fabularium_publication(
  target_submission_id uuid,
  failure_message text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;

  update public.fabularium_submissions
  set
    status = 'approved',
    publication_error = left(
      coalesce(
        nullif(failure_message, ''),
        'Official publication failed'
      ),
      2000
    )
  where id = target_submission_id
    and status in ('approved', 'publishing');
end;
$$;

revoke all on function
  public.worker_fail_fabularium_publication(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.worker_fail_fabularium_publication(uuid, text)
to service_role;

create or replace function public.worker_finalize_fabularium_publication(
  payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_submission_id uuid := (payload->>'submissionId')::uuid;
  v_model_id text := nullif(payload->>'modelId', '');
  v_package_id text := nullif(payload->>'packageId', '');
  v_submission public.fabularium_submissions%rowtype;
  v_score_rows integer := 0;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;

  select *
  into v_submission
  from public.fabularium_submissions
  where id = v_submission_id
  for update;

  if not found then
    raise exception 'Submission not found';
  end if;

  if v_submission.status <> 'publishing' then
    raise exception 'Submission is not publishing';
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
    contributor_id,
    deleted_at
  )
  values (
    v_model_id,
    v_submission.name,
    v_submission.studio,
    v_submission.category,
    v_submission.model_type,
    v_submission.scale,
    v_submission.height,
    v_submission.description,
    v_submission.tags,
    v_submission.submitted_by,
    null
  );

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
    telegram_catalog_access_hash,
    telegram_catalog_anchor_message_id,
    telegram_files_channel_id,
    telegram_files_channel_title,
    telegram_files_access_hash,
    telegram_files_header_message_id,
    telegram_manifest_message_id,
    manifest_json,
    package_created_at,
    submitted_by,
    storage_key,
    content_fingerprint,
    published_at,
    deleted_at
  )
  values (
    v_package_id,
    v_model_id,
    'published',
    coalesce(v_submission.source_folder_name, ''),
    case
      when v_submission.source_size > 0
        then v_submission.source_size
      else v_submission.archive_size
    end,
    payload->>'archiveFileName',
    v_submission.archive_size,
    coalesce(v_submission.archive_sha256, ''),
    jsonb_array_length(coalesce(payload->'parts', '[]'::jsonb)),
    (payload->'telegram'->'catalog'->>'channelId')::bigint,
    payload->'telegram'->'catalog'->>'channelTitle',
    (payload->'telegram'->'catalog'->>'accessHash')::bigint,
    (payload->'telegram'->'catalog'->>'anchorMessageId')::bigint,
    (payload->'telegram'->'files'->>'channelId')::bigint,
    payload->'telegram'->'files'->>'channelTitle',
    (payload->'telegram'->'files'->>'accessHash')::bigint,
    (payload->'telegram'->'files'->>'headerMessageId')::bigint,
    (payload->'telegram'->'files'->>'manifestMessageId')::bigint,
    coalesce(payload->'manifest', '{}'::jsonb),
    now(),
    v_submission.submitted_by,
    v_submission.storage_key,
    v_submission.content_fingerprint,
    now(),
    null
  );

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
    item->>'fileName',
    (item->>'size')::bigint,
    item->>'sha256',
    (item->>'messageId')::bigint
  from jsonb_array_elements(
    coalesce(payload->'parts', '[]'::jsonb)
  ) as parts(item);

  update public.fabularium_models
  set
    active_package_id = v_package_id,
    deleted_at = null
  where model_id = v_model_id;

  update public.fabularium_submissions
  set
    status = 'published',
    published_model_id = v_model_id,
    published_package_id = v_package_id,
    published_at = now(),
    publication_error = null
  where id = v_submission_id;

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
    'submission-approved:' || v_submission_id::text,
    20,
    5
  )
  on conflict (source_key) do nothing;

  get diagnostics v_score_rows = row_count;

  if v_score_rows > 0 then
    update public.fabularium_profiles
    set approved_uploads = approved_uploads + 1
    where user_id = v_submission.submitted_by;
  end if;
end;
$$;

revoke all on function
  public.worker_finalize_fabularium_publication(jsonb)
from public, anon, authenticated;

grant execute on function
  public.worker_finalize_fabularium_publication(jsonb)
to service_role;

create or replace function public.worker_clear_fabularium_pending(
  target_submission_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;

  update public.fabularium_submissions
  set
    pending_channel_id = null,
    pending_header_message_id = null,
    pending_file_message_ids = '{}'::bigint[],
    pending_manifest_message_id = null,
    storage_key = case
      when status = 'rejected'
        then null
      else storage_key
    end
  where id = target_submission_id;
end;
$$;

revoke all on function
  public.worker_clear_fabularium_pending(uuid)
from public, anon, authenticated;

grant execute on function
  public.worker_clear_fabularium_pending(uuid)
to service_role;

commit;
