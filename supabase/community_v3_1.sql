-- ============================================================
-- Fabularium Community V3.1 - Submission Intake
-- ============================================================
-- Apply AFTER Community Foundation V2.
--
-- This migration adds the server-side intake state used by the
-- Fabularium Worker. Heavy archives are streamed directly to the Worker,
-- never to Supabase Storage.
-- ============================================================

begin;

alter table public.fabularium_submissions
  add column if not exists upload_error text;

alter table public.fabularium_submissions
  add column if not exists uploaded_at timestamptz;

create table if not exists public.fabularium_upload_jobs (
  id uuid primary key default gen_random_uuid(),

  submission_id uuid not null unique
    references public.fabularium_submissions(id)
    on delete cascade,

  status text not null default 'queued'
    check (
      status in (
        'queued',
        'receiving',
        'received',
        'processing',
        'completed',
        'failed'
      )
    ),

  worker_id text,
  file_name text,
  expected_bytes bigint not null default 0,
  received_bytes bigint not null default 0,
  error_message text,

  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists
  fabularium_upload_jobs_status_idx
on public.fabularium_upload_jobs(
  status,
  created_at
);

alter table public.fabularium_upload_jobs
  enable row level security;

drop policy if exists
  "Fabularium upload job owner read"
on public.fabularium_upload_jobs;

create policy "Fabularium upload job owner read"
on public.fabularium_upload_jobs
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

revoke all on public.fabularium_upload_jobs
  from anon, authenticated;

grant select on public.fabularium_upload_jobs
  to authenticated;

grant all on public.fabularium_upload_jobs
  to service_role;

create or replace function public.touch_fabularium_upload_job_updated_at()
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
  touch_fabularium_upload_jobs_updated_at
on public.fabularium_upload_jobs;

create trigger touch_fabularium_upload_jobs_updated_at
before update on public.fabularium_upload_jobs
for each row
execute function public.touch_fabularium_upload_job_updated_at();

-- ------------------------------------------------------------
-- Worker: upload started
-- ------------------------------------------------------------

create or replace function public.worker_start_fabularium_upload(
  target_submission_id uuid,
  worker_identifier text,
  upload_file_name text,
  expected_size bigint
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

  if expected_size <= 0 then
    raise exception 'Invalid upload size';
  end if;

  update public.fabularium_submissions
  set
    status = 'uploading',
    archive_file_name = nullif(upload_file_name, ''),
    archive_size = expected_size,
    upload_error = null
  where id = target_submission_id
    and status in (
      'uploading',
      'failed'
    );

  if not found then
    raise exception 'Submission not found or cannot accept an upload';
  end if;

  insert into public.fabularium_upload_jobs (
    submission_id,
    status,
    worker_id,
    file_name,
    expected_bytes,
    received_bytes,
    error_message,
    started_at,
    completed_at
  )
  values (
    target_submission_id,
    'receiving',
    nullif(worker_identifier, ''),
    nullif(upload_file_name, ''),
    expected_size,
    0,
    null,
    now(),
    null
  )
  on conflict (submission_id) do update
  set
    status = 'receiving',
    worker_id = excluded.worker_id,
    file_name = excluded.file_name,
    expected_bytes = excluded.expected_bytes,
    received_bytes = 0,
    error_message = null,
    started_at = now(),
    completed_at = null;
end;
$$;

revoke all on function
  public.worker_start_fabularium_upload(
    uuid,
    text,
    text,
    bigint
  )
from public, anon, authenticated;

grant execute on function
  public.worker_start_fabularium_upload(
    uuid,
    text,
    text,
    bigint
  )
to service_role;

-- ------------------------------------------------------------
-- Worker: archive received
-- ------------------------------------------------------------

create or replace function public.worker_complete_fabularium_upload(
  target_submission_id uuid,
  received_file_name text,
  received_size bigint
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
    status = 'uploaded',
    archive_file_name = nullif(received_file_name, ''),
    archive_size = received_size,
    upload_error = null,
    uploaded_at = now()
  where id = target_submission_id
    and status = 'uploading';

  if not found then
    raise exception 'Submission not found or upload is not active';
  end if;

  update public.fabularium_upload_jobs
  set
    status = 'received',
    received_bytes = received_size,
    error_message = null,
    completed_at = now()
  where submission_id = target_submission_id;
end;
$$;

revoke all on function
  public.worker_complete_fabularium_upload(
    uuid,
    text,
    bigint
  )
from public, anon, authenticated;

grant execute on function
  public.worker_complete_fabularium_upload(
    uuid,
    text,
    bigint
  )
to service_role;

-- ------------------------------------------------------------
-- Worker: archive intake failed
-- ------------------------------------------------------------

create or replace function public.worker_fail_fabularium_upload(
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
    status = 'failed',
    upload_error = left(
      coalesce(
        nullif(failure_message, ''),
        'Worker upload failed'
      ),
      2000
    )
  where id = target_submission_id
    and status in (
      'uploading',
      'failed'
    );

  update public.fabularium_upload_jobs
  set
    status = 'failed',
    error_message = left(
      coalesce(
        nullif(failure_message, ''),
        'Worker upload failed'
      ),
      2000
    ),
    completed_at = now()
  where submission_id = target_submission_id;
end;
$$;

revoke all on function
  public.worker_fail_fabularium_upload(
    uuid,
    text
  )
from public, anon, authenticated;

grant execute on function
  public.worker_fail_fabularium_upload(
    uuid,
    text
  )
to service_role;

commit;
