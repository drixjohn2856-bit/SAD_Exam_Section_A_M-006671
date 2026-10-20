create extension if not exists pgcrypto;

create type public.profile_role as enum ('Scholar', 'Staff');
create type public.award_status as enum ('Active', 'Inactive');
create type public.verification_status as enum ('Pending', 'Verified', 'Returned');
create type public.compliance_result as enum ('Not Evaluated', 'Compliant', 'With Deficiency');
create type public.renewal_decision as enum ('Undecided', 'Approved', 'Held');

create table public.profiles (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete set null,
  student_id text unique,
  full_name text not null check (length(trim(full_name)) > 0),
  role public.profile_role not null default 'Scholar',
  created_at timestamptz not null default now(),
  constraint staff_has_no_student_id check (role <> 'Staff' or student_id is null)
);

create table public.scholarship_programs (
  id uuid primary key default gen_random_uuid(),
  program_name text not null unique,
  maximum_gwa numeric(3,2) not null check (maximum_gwa between 1.00 and 5.00),
  minimum_enrolled_units integer not null check (minimum_enrolled_units >= 0),
  allowed_failed_subjects integer not null check (allowed_failed_subjects >= 0),
  allowed_incomplete_grades integer not null check (allowed_incomplete_grades >= 0),
  allowed_dropped_subjects integer not null check (allowed_dropped_subjects >= 0),
  evidence_required boolean not null default true,
  submission_deadline timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.scholar_assignments (
  id uuid primary key default gen_random_uuid(),
  scholar_profile_id uuid not null references public.profiles(id) on delete restrict,
  program_id uuid not null references public.scholarship_programs(id) on delete restrict,
  assigned_at timestamptz not null default now(),
  award_status public.award_status not null default 'Active',
  unique (scholar_profile_id),
  unique (id, scholar_profile_id)
);

create table public.semester_submissions (
  id uuid primary key default gen_random_uuid(),
  scholar_profile_id uuid not null references public.profiles(id) on delete restrict,
  assignment_id uuid not null references public.scholar_assignments(id) on delete restrict,
  academic_year text not null check (academic_year ~ '^[0-9]{4}-[0-9]{4}$'),
  semester text not null check (semester in ('1', '2', 'Summer')),
  gwa numeric(3,2) not null check (gwa between 1.00 and 5.00),
  enrolled_units integer not null check (enrolled_units >= 0),
  failed_count integer not null check (failed_count >= 0),
  incomplete_count integer not null check (incomplete_count >= 0),
  dropped_count integer not null check (dropped_count >= 0),
  grade_document_ref text not null check (length(trim(grade_document_ref)) > 0),
  submitted_at timestamptz not null default now(),
  verification_status public.verification_status not null default 'Pending',
  verification_reason text,
  verified_by uuid references public.profiles(id),
  verified_at timestamptz,
  compliance_result public.compliance_result not null default 'Not Evaluated',
  compliance_reasons jsonb not null default '[]'::jsonb check (jsonb_typeof(compliance_reasons) = 'array'),
  policy_check_details jsonb not null default '{}'::jsonb,
  evaluated_by uuid references public.profiles(id),
  evaluated_at timestamptz,
  renewal_decision public.renewal_decision not null default 'Undecided',
  decision_notes text,
  decided_by uuid references public.profiles(id),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (scholar_profile_id, academic_year, semester),
  constraint assignment_belongs_to_scholar foreign key (assignment_id, scholar_profile_id)
    references public.scholar_assignments(id, scholar_profile_id) on delete restrict
);

create table public.submission_history (
  id bigint generated always as identity primary key,
  submission_id uuid not null references public.semester_submissions(id) on delete restrict,
  action_type text not null,
  old_values jsonb not null default '{}'::jsonb,
  new_values jsonb not null default '{}'::jsonb,
  notes text,
  acting_user_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  idempotency_key text unique
);

create index submissions_assignment_period_idx
  on public.semester_submissions (academic_year, semester, assignment_id);
create index submissions_scholar_idx on public.semester_submissions (scholar_profile_id);
create index history_submission_created_idx on public.submission_history (submission_id, created_at desc);

create function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
create trigger submissions_touch_updated_at before update on public.semester_submissions
for each row execute function public.touch_updated_at();

create function public.create_scholar_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (auth_user_id, student_id, full_name, role)
  values (
    new.id,
    nullif(trim(new.raw_user_meta_data ->> 'student_id'), ''),
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), 'Scholar'),
    'Scholar'
  );
  return new;
end;
$$;
revoke all on function public.create_scholar_profile() from public, anon, authenticated;
create trigger auth_user_scholar_profile after insert on auth.users
for each row execute function public.create_scholar_profile();

create function public.is_staff()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.auth_user_id = auth.uid() and p.role = 'Staff'
  );
$$;
revoke all on function public.is_staff() from public, anon;
grant execute on function public.is_staff() to authenticated;

alter table public.profiles enable row level security;
alter table public.scholarship_programs enable row level security;
alter table public.scholar_assignments enable row level security;
alter table public.semester_submissions enable row level security;
alter table public.submission_history enable row level security;

create policy profiles_read_self_or_staff on public.profiles for select to authenticated
  using (auth_user_id = (select auth.uid()) or (select public.is_staff()));
create policy programs_read_authenticated on public.scholarship_programs for select to authenticated using (true);
create policy assignments_read_self_or_staff on public.scholar_assignments for select to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = scholar_profile_id and p.auth_user_id = (select auth.uid()))
    or (select public.is_staff())
  );
create policy submissions_read_self_or_staff on public.semester_submissions for select to authenticated
  using (
    exists (select 1 from public.profiles p where p.id = scholar_profile_id and p.auth_user_id = (select auth.uid()))
    or (select public.is_staff())
  );
create policy history_read_self_or_staff on public.submission_history for select to authenticated
  using (
    exists (
      select 1 from public.semester_submissions s join public.profiles p on p.id = s.scholar_profile_id
      where s.id = submission_id and p.auth_user_id = (select auth.uid())
    )
    or (select public.is_staff())
  );

revoke all on public.profiles, public.scholarship_programs, public.scholar_assignments,
  public.semester_submissions, public.submission_history from anon, authenticated;
grant select on public.profiles, public.scholarship_programs, public.scholar_assignments,
  public.semester_submissions, public.submission_history to authenticated;
grant usage, select on sequence public.submission_history_id_seq to authenticated;

create function public.write_submission_history(
  p_submission_id uuid, p_action text, p_old jsonb, p_new jsonb, p_notes text default null
)
returns void language sql security definer set search_path = '' as $$
  insert into public.submission_history (submission_id, action_type, old_values, new_values, notes, acting_user_id)
  values (p_submission_id, p_action, coalesce(p_old, '{}'::jsonb), coalesce(p_new, '{}'::jsonb), p_notes, auth.uid());
$$;
revoke all on function public.write_submission_history(uuid, text, jsonb, jsonb, text) from public, anon, authenticated;

create function public.submit_semester_submission(
  p_academic_year text, p_semester text, p_gwa numeric, p_enrolled_units integer,
  p_failed_count integer, p_incomplete_count integer, p_dropped_count integer, p_grade_document_ref text
)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_assignment public.scholar_assignments%rowtype;
  v_submission_id uuid;
begin
  select * into v_profile from public.profiles where auth_user_id = auth.uid() and role = 'Scholar';
  if not found then raise exception 'Scholar profile is required to submit.' using errcode = '42501'; end if;
  select * into v_assignment from public.scholar_assignments
    where scholar_profile_id = v_profile.id and award_status = 'Active';
  if not found then raise exception 'No active scholarship assignment was found.' using errcode = 'P0001'; end if;
  insert into public.semester_submissions (
    scholar_profile_id, assignment_id, academic_year, semester, gwa, enrolled_units,
    failed_count, incomplete_count, dropped_count, grade_document_ref
  ) values (
    v_profile.id, v_assignment.id, p_academic_year, p_semester, p_gwa, p_enrolled_units,
    p_failed_count, p_incomplete_count, p_dropped_count, trim(p_grade_document_ref)
  ) returning id into v_submission_id;
  perform public.write_submission_history(v_submission_id, 'submitted', '{}'::jsonb,
    jsonb_build_object('verification_status', 'Pending', 'compliance_result', 'Not Evaluated',
      'renewal_decision', 'Undecided', 'gwa', p_gwa, 'academic_year', p_academic_year, 'semester', p_semester),
    'Scholar submitted academic summary.');
  return v_submission_id;
end;
$$;

create function public.resubmit_returned_submission(
  p_submission_id uuid, p_academic_year text, p_semester text, p_gwa numeric, p_enrolled_units integer,
  p_failed_count integer, p_incomplete_count integer, p_dropped_count integer, p_grade_document_ref text
)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_old jsonb;
  v_scholar_id uuid;
begin
  select to_jsonb(s), s.scholar_profile_id into v_old, v_scholar_id
  from public.semester_submissions s where s.id = p_submission_id for update;
  if not found or not exists (
    select 1 from public.profiles where id = v_scholar_id and auth_user_id = auth.uid() and role = 'Scholar'
  ) then raise exception 'Submission not found or not owned by this Scholar.' using errcode = '42501'; end if;
  if (v_old ->> 'verification_status') <> 'Returned' then
    raise exception 'Only a Returned submission can be corrected.' using errcode = 'P0001';
  end if;
  update public.semester_submissions set
    academic_year = p_academic_year, semester = p_semester, gwa = p_gwa,
    enrolled_units = p_enrolled_units, failed_count = p_failed_count,
    incomplete_count = p_incomplete_count, dropped_count = p_dropped_count,
    grade_document_ref = trim(p_grade_document_ref), submitted_at = now(),
    verification_status = 'Pending', verification_reason = null, verified_by = null, verified_at = null,
    compliance_result = 'Not Evaluated', compliance_reasons = '[]'::jsonb, policy_check_details = '{}'::jsonb,
    evaluated_by = null, evaluated_at = null, renewal_decision = 'Undecided',
    decision_notes = null, decided_by = null, decided_at = null
  where id = p_submission_id;
  perform public.write_submission_history(p_submission_id, 'resubmitted', v_old,
    jsonb_build_object('verification_status', 'Pending', 'compliance_result', 'Not Evaluated',
      'renewal_decision', 'Undecided', 'submitted_at', now()), 'Scholar corrected and resubmitted.');
end;
$$;

create function public.set_submission_verification(p_submission_id uuid, p_status text, p_reason text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.semester_submissions%rowtype;
  v_old jsonb;
begin
  if not public.is_staff() then raise exception 'Staff role required.' using errcode = '42501'; end if;
  if p_status is null or p_status not in ('Verified', 'Returned') then
    raise exception 'Verification status must be Verified or Returned.';
  end if;
  if p_status = 'Returned' and length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'A correction reason is required when returning evidence.';
  end if;
  select * into v_row from public.semester_submissions where id = p_submission_id for update;
  if not found then raise exception 'Submission not found.'; end if;
  if p_status = 'Verified' and length(trim(v_row.grade_document_ref)) = 0 then
    raise exception 'A grade document reference is required before verification.';
  end if;
  v_old := to_jsonb(v_row);
  update public.semester_submissions set
    verification_status = p_status, verification_reason = case when p_status = 'Returned' then trim(p_reason) else null end,
    verified_by = case when p_status = 'Verified' then (select id from public.profiles where auth_user_id = auth.uid()) else null end,
    verified_at = case when p_status = 'Verified' then now() else null end,
    compliance_result = 'Not Evaluated', compliance_reasons = '[]'::jsonb,
    policy_check_details = '{}'::jsonb, evaluated_by = null, evaluated_at = null,
    renewal_decision = 'Undecided', decision_notes = null, decided_by = null, decided_at = null
  where id = p_submission_id;
  perform public.write_submission_history(p_submission_id, 'verification_changed', v_old,
    jsonb_build_object('verification_status', p_status, 'verification_reason', case when p_status = 'Returned' then trim(p_reason) else null end,
      'compliance_result', 'Not Evaluated', 'renewal_decision', 'Undecided'), p_reason);
end;
$$;

create function public.evaluate_submission(p_submission_id uuid)
returns public.compliance_result language plpgsql security definer set search_path = '' as $$
declare
  v_row public.semester_submissions%rowtype;
  v_policy public.scholarship_programs%rowtype;
  v_checks jsonb;
  v_policy_details jsonb;
  v_reasons jsonb := '[]'::jsonb;
  v_result public.compliance_result;
  v_actor uuid;
begin
  if not public.is_staff() then raise exception 'Staff role required.' using errcode = '42501'; end if;
  select * into v_row from public.semester_submissions where id = p_submission_id for update;
  if not found then raise exception 'Submission not found.'; end if;
  if v_row.verification_status <> 'Verified' then
    raise exception 'Evidence must be Verified before evaluation.' using errcode = 'P0001';
  end if;
  select p.* into v_policy from public.scholarship_programs p
    join public.scholar_assignments a on a.program_id = p.id where a.id = v_row.assignment_id;
  if not found then raise exception 'Scholarship policy not found.'; end if;
  if v_policy.evidence_required and length(trim(v_row.grade_document_ref)) = 0 then
    raise exception 'Required grade document reference is missing.' using errcode = 'P0001';
  end if;
  v_checks := jsonb_build_array(
    jsonb_build_object('key','gwa','label','GWA','actual',v_row.gwa,'threshold',v_policy.maximum_gwa,'pass',v_row.gwa <= v_policy.maximum_gwa),
    jsonb_build_object('key','units','label','Enrolled units','actual',v_row.enrolled_units,'threshold',v_policy.minimum_enrolled_units,'pass',v_row.enrolled_units >= v_policy.minimum_enrolled_units),
    jsonb_build_object('key','failed','label','Failed subjects','actual',v_row.failed_count,'threshold',v_policy.allowed_failed_subjects,'pass',v_row.failed_count <= v_policy.allowed_failed_subjects),
    jsonb_build_object('key','incomplete','label','Incomplete grades','actual',v_row.incomplete_count,'threshold',v_policy.allowed_incomplete_grades,'pass',v_row.incomplete_count <= v_policy.allowed_incomplete_grades),
    jsonb_build_object('key','dropped','label','Dropped subjects','actual',v_row.dropped_count,'threshold',v_policy.allowed_dropped_subjects,'pass',v_row.dropped_count <= v_policy.allowed_dropped_subjects),
    jsonb_build_object('key','deadline','label','Submission deadline','actual',v_row.submitted_at,'threshold',v_policy.submission_deadline,'pass',v_row.submitted_at <= v_policy.submission_deadline)
  );
  if v_row.gwa > v_policy.maximum_gwa then v_reasons := v_reasons || jsonb_build_array(format('GWA %s exceeds the maximum of %s.', v_row.gwa, v_policy.maximum_gwa)); end if;
  if v_row.enrolled_units < v_policy.minimum_enrolled_units then v_reasons := v_reasons || jsonb_build_array(format('%s enrolled units is below the required %s.', v_row.enrolled_units, v_policy.minimum_enrolled_units)); end if;
  if v_row.failed_count > v_policy.allowed_failed_subjects then v_reasons := v_reasons || jsonb_build_array(format('%s failed subject(s) exceeds the allowed %s.', v_row.failed_count, v_policy.allowed_failed_subjects)); end if;
  if v_row.incomplete_count > v_policy.allowed_incomplete_grades then v_reasons := v_reasons || jsonb_build_array(format('%s incomplete grade(s) exceeds the allowed %s.', v_row.incomplete_count, v_policy.allowed_incomplete_grades)); end if;
  if v_row.dropped_count > v_policy.allowed_dropped_subjects then v_reasons := v_reasons || jsonb_build_array(format('%s dropped subject(s) exceeds the allowed %s.', v_row.dropped_count, v_policy.allowed_dropped_subjects)); end if;
  if v_row.submitted_at > v_policy.submission_deadline then v_reasons := v_reasons || jsonb_build_array('Submitted after the deadline.'); end if;
  v_result := case when jsonb_array_length(v_reasons) = 0 then 'Compliant'::public.compliance_result else 'With Deficiency'::public.compliance_result end;
  select id into v_actor from public.profiles where auth_user_id = auth.uid();
  v_policy_details := jsonb_build_object(
    'evaluated_at', now(), 'program_name', v_policy.program_name,
    'maximum_gwa',v_policy.maximum_gwa,'minimum_enrolled_units',v_policy.minimum_enrolled_units,
    'allowed_failed_subjects',v_policy.allowed_failed_subjects,
    'allowed_incomplete_grades',v_policy.allowed_incomplete_grades,
    'allowed_dropped_subjects',v_policy.allowed_dropped_subjects,
    'evidence_required',v_policy.evidence_required,'submission_deadline',v_policy.submission_deadline,
    'checks',v_checks
  );
  update public.semester_submissions set compliance_result = v_result, compliance_reasons = v_reasons,
    policy_check_details = v_policy_details,
    evaluated_by = v_actor, evaluated_at = now(), renewal_decision = 'Undecided',
    decision_notes = null, decided_by = null, decided_at = null
  where id = p_submission_id;
  perform public.write_submission_history(p_submission_id, 'evaluated', to_jsonb(v_row),
    jsonb_build_object('compliance_result',v_result,'compliance_reasons',v_reasons,'policy_check_details',v_policy_details),
    'Policy evaluated against a persisted policy snapshot.');
  return v_result;
end;
$$;

create function public.decide_renewal(p_submission_id uuid, p_decision text, p_notes text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.semester_submissions%rowtype;
  v_old jsonb;
  v_actor uuid;
begin
  if not public.is_staff() then raise exception 'Staff role required.' using errcode = '42501'; end if;
  if p_decision is null or p_decision not in ('Approved', 'Held') then
    raise exception 'Decision must be Approved or Held.';
  end if;
  if p_decision = 'Held' and length(trim(coalesce(p_notes, ''))) = 0 then
    raise exception 'A reason is required when holding renewal.';
  end if;
  select * into v_row from public.semester_submissions where id = p_submission_id for update;
  if not found then raise exception 'Submission not found.'; end if;
  if v_row.verification_status <> 'Verified' or v_row.compliance_result = 'Not Evaluated' then
    raise exception 'A Verified, evaluated submission is required before a renewal decision.' using errcode = 'P0001';
  end if;
  if p_decision = 'Approved' and v_row.compliance_result <> 'Compliant' then
    raise exception 'Approval requires a Compliant evaluation.' using errcode = 'P0001';
  end if;
  v_old := to_jsonb(v_row);
  select id into v_actor from public.profiles where auth_user_id = auth.uid();
  update public.semester_submissions set renewal_decision = p_decision, decision_notes = nullif(trim(p_notes), ''),
    decided_by = v_actor, decided_at = now() where id = p_submission_id;
  perform public.write_submission_history(p_submission_id, 'renewal_decided', v_old,
    jsonb_build_object('renewal_decision',p_decision,'decision_notes',nullif(trim(p_notes),'')),
    nullif(trim(p_notes),''));
end;
$$;

create function public.register_scholar(p_student_id text, p_full_name text, p_program_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_id uuid;
begin
  if not public.is_staff() then raise exception 'Staff role required.' using errcode = '42501'; end if;
  if length(trim(coalesce(p_student_id,''))) = 0 or length(trim(coalesce(p_full_name,''))) = 0 then
    raise exception 'Student ID and full name are required.';
  end if;
  insert into public.profiles(student_id, full_name, role)
  values (trim(p_student_id), trim(p_full_name), 'Scholar') returning id into v_id;
  insert into public.scholar_assignments(scholar_profile_id, program_id) values (v_id, p_program_id);
  return v_id;
end;
$$;

create function public.link_scholar_auth_user(p_student_id text, p_auth_user_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_scholar_id uuid; v_existing_id uuid;
begin
  if not public.is_staff() then raise exception 'Staff role required.' using errcode = '42501'; end if;
  select id into v_scholar_id from public.profiles where student_id = trim(p_student_id) and role = 'Scholar' for update;
  if not found then raise exception 'Scholar profile not found.'; end if;
  select id into v_existing_id from public.profiles where auth_user_id = p_auth_user_id for update;
  if v_existing_id is null then raise exception 'Auth user not found or does not have an automatically created Scholar profile.'; end if;
  if exists (select 1 from public.profiles where auth_user_id = p_auth_user_id and role <> 'Scholar') then
    raise exception 'Staff accounts cannot be linked to Scholar records.';
  end if;
  if exists (select 1 from public.profiles where id = v_scholar_id and auth_user_id is not null and auth_user_id <> p_auth_user_id) then
    raise exception 'Scholar record is already linked to another Auth user.';
  end if;
  delete from public.profiles where id = v_existing_id and id <> v_scholar_id and student_id is null;
  update public.profiles set auth_user_id = p_auth_user_id where id = v_scholar_id;
end;
$$;

revoke all on function public.submit_semester_submission(text,text,numeric,integer,integer,integer,integer,text) from public, anon;
revoke all on function public.resubmit_returned_submission(uuid,text,text,numeric,integer,integer,integer,integer,text) from public, anon;
revoke all on function public.set_submission_verification(uuid,text,text) from public, anon;
revoke all on function public.evaluate_submission(uuid) from public, anon;
revoke all on function public.decide_renewal(uuid,text,text) from public, anon;
revoke all on function public.register_scholar(text,text,uuid) from public, anon;
revoke all on function public.link_scholar_auth_user(text,uuid) from public, anon;
grant execute on function public.submit_semester_submission(text,text,numeric,integer,integer,integer,integer,text) to authenticated;
grant execute on function public.resubmit_returned_submission(uuid,text,text,numeric,integer,integer,integer,integer,text) to authenticated;
grant execute on function public.set_submission_verification(uuid,text,text) to authenticated;
grant execute on function public.evaluate_submission(uuid) to authenticated;
grant execute on function public.decide_renewal(uuid,text,text) to authenticated;
grant execute on function public.register_scholar(text,text,uuid) to authenticated;
grant execute on function public.link_scholar_auth_user(text,uuid) to authenticated;
