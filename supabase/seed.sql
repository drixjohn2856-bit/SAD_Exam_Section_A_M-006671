-- Synthetic, repeatable seed data. Run after the initial migration; no Auth credentials are created.
insert into public.scholarship_programs (
  program_name, maximum_gwa, minimum_enrolled_units, allowed_failed_subjects,
  allowed_incomplete_grades, allowed_dropped_subjects, evidence_required, submission_deadline
) values
  ('Merit Scholar', 1.75, 18, 0, 0, 0, true, '2026-10-30 17:00:00+08'),
  ('Community Scholar', 2.25, 15, 0, 0, 1, true, '2026-10-30 17:00:00+08')
on conflict (program_name) do update set
  maximum_gwa = excluded.maximum_gwa, minimum_enrolled_units = excluded.minimum_enrolled_units,
  allowed_failed_subjects = excluded.allowed_failed_subjects,
  allowed_incomplete_grades = excluded.allowed_incomplete_grades,
  allowed_dropped_subjects = excluded.allowed_dropped_subjects,
  evidence_required = excluded.evidence_required, submission_deadline = excluded.submission_deadline;

insert into public.profiles (student_id, full_name, role) values
  ('A01','Althea Reyes','Scholar'),('A02','Benjamin Cruz','Scholar'),
  ('A03','Camille Santos','Scholar'),('A04','Daniel Lim','Scholar'),
  ('A05','Elena Garcia','Scholar'),('A06','Felix Mendoza','Scholar')
on conflict (student_id) do update set full_name = excluded.full_name;

insert into public.scholar_assignments (scholar_profile_id, program_id, award_status)
select p.id, sp.id, 'Active' from (values
  ('A01','Merit Scholar'),('A02','Merit Scholar'),('A03','Community Scholar'),
  ('A04','Community Scholar'),('A05','Merit Scholar'),('A06','Community Scholar')
) as seed(student_id, program_name)
join public.profiles p on p.student_id = seed.student_id
join public.scholarship_programs sp on sp.program_name = seed.program_name
on conflict (scholar_profile_id) do update set program_id = excluded.program_id, award_status = 'Active';

insert into public.semester_submissions (
  scholar_profile_id, assignment_id, academic_year, semester, gwa, enrolled_units,
  failed_count, incomplete_count, dropped_count, grade_document_ref, submitted_at,
  verification_status, compliance_result, compliance_reasons, policy_check_details, renewal_decision
)
select p.id, a.id, '2026-2027', '1', seed.gwa, seed.units, seed.failed, seed.incomplete, seed.dropped,
  'synthetic://grade-document/' || seed.student_id, seed.submitted_at,
  seed.verification::public.verification_status, seed.result, seed.reasons,
  jsonb_build_object('seed_expectation',true,'checks',seed.checks,'program_name',sp.program_name,
    'maximum_gwa',sp.maximum_gwa,'minimum_enrolled_units',sp.minimum_enrolled_units,
    'allowed_failed_subjects',sp.allowed_failed_subjects,'allowed_incomplete_grades',sp.allowed_incomplete_grades,
    'allowed_dropped_subjects',sp.allowed_dropped_subjects,'evidence_required',sp.evidence_required,
    'submission_deadline',sp.submission_deadline),
  'Undecided'
from (values
  ('A01',1.75::numeric,18,0,0,0,'2026-10-30 17:00:00+08'::timestamptz,'Verified','Compliant'::public.compliance_result,'[]'::jsonb,
    jsonb_build_array(jsonb_build_object('key','gwa','label','GWA','actual',1.75,'threshold',1.75,'pass',true),jsonb_build_object('key','deadline','label','Submission deadline','actual','2026-10-30T17:00:00+08:00','threshold','2026-10-30T17:00:00+08:00','pass',true))),
  ('A02',1.76::numeric,18,0,0,0,'2026-10-29 17:00:00+08'::timestamptz,'Verified','With Deficiency'::public.compliance_result,'["GWA 1.76 exceeds the maximum of 1.75."]'::jsonb,
    jsonb_build_array(jsonb_build_object('key','gwa','label','GWA','actual',1.76,'threshold',1.75,'pass',false))),
  ('A03',2.25::numeric,15,0,0,1,'2026-10-29 17:00:00+08'::timestamptz,'Verified','Compliant'::public.compliance_result,'[]'::jsonb,
    jsonb_build_array(jsonb_build_object('key','dropped','label','Dropped subjects','actual',1,'threshold',1,'pass',true))),
  ('A04',2.25::numeric,14,0,1,0,'2026-10-29 17:00:00+08'::timestamptz,'Verified','With Deficiency'::public.compliance_result,
    '["14 enrolled units is below the required 15.","1 incomplete grade(s) exceeds the allowed 0."]'::jsonb,
    jsonb_build_array(jsonb_build_object('key','units','label','Enrolled units','actual',14,'threshold',15,'pass',false),jsonb_build_object('key','incomplete','label','Incomplete grades','actual',1,'threshold',0,'pass',false))),
  ('A05',1.50::numeric,18,1,0,0,'2026-10-30 17:01:00+08'::timestamptz,'Verified','With Deficiency'::public.compliance_result,
    '["1 failed subject(s) exceeds the allowed 0.","Submitted after the deadline."]'::jsonb,
    jsonb_build_array(jsonb_build_object('key','failed','label','Failed subjects','actual',1,'threshold',0,'pass',false),jsonb_build_object('key','deadline','label','Submission deadline','actual','2026-10-30T17:01:00+08:00','threshold','2026-10-30T17:00:00+08:00','pass',false))),
  ('A06',2.00::numeric,15,0,0,0,'2026-10-29 17:00:00+08'::timestamptz,'Pending','Not Evaluated'::public.compliance_result,'[]'::jsonb,'[]'::jsonb)
) as seed(student_id,gwa,units,failed,incomplete,dropped,submitted_at,verification,result,reasons,checks)
join public.profiles p on p.student_id = seed.student_id
join public.scholar_assignments a on a.scholar_profile_id = p.id
join public.scholarship_programs sp on sp.id = a.program_id
on conflict (scholar_profile_id, academic_year, semester) do update set
  assignment_id = excluded.assignment_id, gwa = excluded.gwa, enrolled_units = excluded.enrolled_units,
  failed_count = excluded.failed_count, incomplete_count = excluded.incomplete_count,
  dropped_count = excluded.dropped_count, grade_document_ref = excluded.grade_document_ref,
  submitted_at = excluded.submitted_at, verification_status = excluded.verification_status,
  verification_reason = null, verified_by = null, verified_at = null,
  compliance_result = excluded.compliance_result, compliance_reasons = excluded.compliance_reasons,
  policy_check_details = excluded.policy_check_details, renewal_decision = 'Undecided',
  evaluated_by = null, evaluated_at = null,
  decision_notes = null, decided_by = null, decided_at = null;

-- Ensure every displayed policy check contains an actual, threshold, and outcome.
update public.semester_submissions s
set policy_check_details = jsonb_build_object(
  'seed_expectation', true, 'program_name', p.program_name,
  'maximum_gwa', p.maximum_gwa, 'minimum_enrolled_units', p.minimum_enrolled_units,
  'allowed_failed_subjects', p.allowed_failed_subjects,
  'allowed_incomplete_grades', p.allowed_incomplete_grades,
  'allowed_dropped_subjects', p.allowed_dropped_subjects,
  'evidence_required', p.evidence_required, 'submission_deadline', p.submission_deadline,
  'checks', jsonb_build_array(
    jsonb_build_object('key','gwa','label','GWA','actual',s.gwa,'threshold',p.maximum_gwa,'pass',s.gwa <= p.maximum_gwa),
    jsonb_build_object('key','units','label','Enrolled units','actual',s.enrolled_units,'threshold',p.minimum_enrolled_units,'pass',s.enrolled_units >= p.minimum_enrolled_units),
    jsonb_build_object('key','failed','label','Failed subjects','actual',s.failed_count,'threshold',p.allowed_failed_subjects,'pass',s.failed_count <= p.allowed_failed_subjects),
    jsonb_build_object('key','incomplete','label','Incomplete grades','actual',s.incomplete_count,'threshold',p.allowed_incomplete_grades,'pass',s.incomplete_count <= p.allowed_incomplete_grades),
    jsonb_build_object('key','dropped','label','Dropped subjects','actual',s.dropped_count,'threshold',p.allowed_dropped_subjects,'pass',s.dropped_count <= p.allowed_dropped_subjects),
    jsonb_build_object('key','deadline','label','Submission deadline','actual',s.submitted_at,'threshold',p.submission_deadline,'pass',s.submitted_at <= p.submission_deadline)
  )
)
from public.scholar_assignments a
join public.scholarship_programs p on p.id = a.program_id
where a.id = s.assignment_id and s.academic_year = '2026-2027' and s.semester = '1'
  and s.scholar_profile_id in (select id from public.profiles where student_id between 'A01' and 'A06');

insert into public.submission_history (submission_id, action_type, new_values, notes, idempotency_key)
select s.id, 'seeded', jsonb_build_object('verification_status',s.verification_status,
  'compliance_result',s.compliance_result,'renewal_decision',s.renewal_decision,
  'policy_snapshot',s.policy_check_details), 'Synthetic baseline record; renewal intentionally undecided.',
  'seed-' || p.student_id
from public.semester_submissions s join public.profiles p on p.id = s.scholar_profile_id
where p.student_id between 'A01' and 'A06' and s.academic_year = '2026-2027' and s.semester = '1'
on conflict (idempotency_key) do nothing;
