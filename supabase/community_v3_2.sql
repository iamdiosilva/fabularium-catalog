-- ============================================================
-- Fabularium Community V3.2 - Telegram Pending Pipeline
-- ============================================================
-- Apply AFTER community_v3_1.sql.
--
-- Adds:
--   - Worker processing state
--   - verified private Telegram Pending publication
--   - automatic duplicate analysis from service_role
--   - sensitive-column protection for normal authenticated users
-- ============================================================

begin;

alter table public.fabularium_submissions
  add column if not exists processing_started_at timestamptz;

alter table public.fabularium_submissions
  add column if not exists pending_uploaded_at timestamptz;

-- ============================================================
-- 1. DO NOT EXPOSE PENDING STORAGE INTERNALS TO NORMAL USERS
-- ============================================================
--
-- RLS controls rows, not individual columns. Previous V2/V3.1 grants allowed
-- the submission owner to SELECT the whole row, which meant a technical user
-- could query pending_channel_id/storage_key directly through PostgREST.
--
-- From V3.2 onward authenticated clients only receive the safe columns below.
-- The Worker still uses service_role and keeps full table access.
-- ============================================================

revoke select on public.fabularium_submissions
from authenticated;

grant select (
  id,
  submitted_by,
  name,
  studio,
  category,
  model_type,
  scale,
  height,
  description,
  tags,
  status,
  duplicate_status,
  duplicate_of_model_id,
  source_folder_name,
  source_size,
  archive_file_name,
  archive_size,
  archive_sha256,
  content_fingerprint,
  published_model_id,
  published_package_id,
  submitted_at,
  updated_at,
  uploaded_at,
  reviewed_at,
  reviewed_by,
  review_note,
  published_at,
  upload_error
) on public.fabularium_submissions
to authenticated;

-- ============================================================
-- 2. WORKER: BEGIN PROCESSING
-- ============================================================

create or replace function public.worker_begin_fabularium_processing(
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
    status = 'processing',
    processing_started_at = now(),
    upload_error = null
  where id = target_submission_id
    and status in (
      'uploaded',
      'processing'
    );

  if not found then
    raise exception 'Submission not found or cannot be processed';
  end if;

  update public.fabularium_upload_jobs
  set
    status = 'processing',
    worker_id = coalesce(
      nullif(worker_identifier, ''),
      worker_id
    ),
    error_message = null,
    completed_at = null
  where submission_id = target_submission_id;
end;
$$;

revoke all on function
  public.worker_begin_fabularium_processing(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.worker_begin_fabularium_processing(uuid, text)
to service_role;

-- ============================================================
-- 3. WORKER: FAILURE NOW ALSO COVERS PROCESSING
-- ============================================================

create or replace function public.worker_fail_fabularium_upload(
  target_submission_id uuid,
  failure_message text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_error text := left(
    coalesce(
      nullif(failure_message, ''),
      'Worker processing failed'
    ),
    2000
  );
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;

  update public.fabularium_submissions
  set
    status = 'failed',
    upload_error = v_error
  where id = target_submission_id
    and status in (
      'uploading',
      'uploaded',
      'processing',
      'failed'
    );

  update public.fabularium_upload_jobs
  set
    status = 'failed',
    error_message = v_error,
    completed_at = now()
  where submission_id = target_submission_id;
end;
$$;

revoke all on function
  public.worker_fail_fabularium_upload(uuid, text)
from public, anon, authenticated;

grant execute on function
  public.worker_fail_fabularium_upload(uuid, text)
to service_role;

-- ============================================================
-- 4. WORKER: VERIFIED PENDING UPLOAD COMPLETE
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
  if auth.role() <> 'service_role' then
    raise exception 'service_role required';
  end if;

  if telegram_channel_id is null then
    raise exception 'Pending Telegram channel is required';
  end if;

  if header_message_id is null or header_message_id <= 0 then
    raise exception 'Pending header message is required';
  end if;

  if coalesce(array_length(file_message_ids, 1), 0) <= 0 then
    raise exception 'At least one Pending file message is required';
  end if;

  if manifest_message_id is null or manifest_message_id <= 0 then
    raise exception 'Pending manifest message is required';
  end if;

  if nullif(storage_key_value, '') is null then
    raise exception 'storageKey is required';
  end if;

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
    status = 'pending_review',
    pending_uploaded_at = now(),
    upload_error = null
  where id = target_submission_id
    and status in (
      'uploaded',
      'processing',
      'failed'
    );

  if not found then
    raise exception 'Submission not found or cannot enter review';
  end if;

  update public.fabularium_upload_jobs
  set
    status = 'completed',
    error_message = null,
    completed_at = now()
  where submission_id = target_submission_id;
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
-- 5. DUPLICATE ANALYSIS: ALLOW THE WORKER
-- ============================================================
--
-- This is the V2 duplicate analysis with one authorization improvement:
-- service_role may run it without auth.uid(), while normal users/admins retain
-- the original ownership checks.
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
  v_is_worker boolean := auth.role() = 'service_role';
begin
  select *
  into v_submission
  from public.fabularium_submissions
  where id = target_submission_id;

  if not found then
    raise exception 'Submission not found';
  end if;

  if not v_is_worker then
    if auth.uid() is null then
      raise exception 'Authentication required';
    end if;

    if v_submission.submitted_by <> auth.uid()
       and not public.is_fabularium_admin() then
      raise exception 'Access denied';
    end if;
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
to authenticated, service_role;

commit;
