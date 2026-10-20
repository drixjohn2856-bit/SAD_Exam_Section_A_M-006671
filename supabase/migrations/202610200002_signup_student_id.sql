create or replace function public.create_scholar_profile()
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
