create or replace function public.assign_new_scholar(p_student_id text, p_program_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.profiles%rowtype;
  v_assignment_id uuid;
begin
  if not public.is_staff() then raise exception 'Staff role required.' using errcode = '42501'; end if;
  select * into v_profile from public.profiles
  where student_id = trim(p_student_id) and role = 'Scholar' for update;
  if not found or v_profile.auth_user_id is null then
    raise exception 'New Auth-backed Scholar profile was not found.' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.scholarship_programs where id = p_program_id) then
    raise exception 'Scholarship program not found.' using errcode = 'P0001';
  end if;
  insert into public.scholar_assignments (scholar_profile_id, program_id, award_status)
  values (v_profile.id, p_program_id, 'Active')
  returning id into v_assignment_id;
  return v_assignment_id;
end;
$$;

create or replace function public.cleanup_unassigned_scholar(p_student_id text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_staff() then raise exception 'Staff role required.' using errcode = '42501'; end if;
  delete from public.profiles p
  where p.student_id = trim(p_student_id)
    and p.role = 'Scholar'
    and p.auth_user_id is not null
    and not exists (select 1 from public.scholar_assignments a where a.scholar_profile_id = p.id)
    and not exists (select 1 from public.semester_submissions s where s.scholar_profile_id = p.id);
  if not found then raise exception 'Unassigned Scholar profile could not be safely removed.' using errcode = 'P0001'; end if;
end;
$$;

revoke all on function public.assign_new_scholar(text, uuid) from public, anon;
revoke all on function public.cleanup_unassigned_scholar(text) from public, anon;
grant execute on function public.assign_new_scholar(text, uuid) to authenticated;
grant execute on function public.cleanup_unassigned_scholar(text) to authenticated;

-- Account provisioning now happens in the server-side Edge Function.
revoke execute on function public.register_scholar(text, text, uuid) from authenticated;
revoke execute on function public.link_scholar_auth_user(text, uuid) from authenticated;
