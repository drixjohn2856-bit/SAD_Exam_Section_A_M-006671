import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return respond(405, { error: 'Method not allowed.' });

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return respond(500, { error: 'Server-side Supabase secrets are not configured.' });
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) return respond(401, { error: 'Staff sign-in is required.' });
  const accessToken = authorization.slice('Bearer '.length);

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch {
    return respond(400, { error: 'Request body must be valid JSON.' });
  }
  const studentId = typeof input.student_id === 'string' ? input.student_id.trim() : '';
  const email = typeof input.email === 'string' ? input.email.trim().toLowerCase() : '';
  const fullName = typeof input.full_name === 'string' ? input.full_name.trim() : '';
  const password = typeof input.temporary_password === 'string' ? input.temporary_password : '';
  const programId = typeof input.program_id === 'string' ? input.program_id : '';
  if (!studentId || !fullName || !email || !programId || password.length < 8) {
    return respond(400, { error: 'Student ID, email, full name, program, and a password of at least 8 characters are required.' });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return respond(400, { error: 'Enter a valid email address.' });

  const staffClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await staffClient.auth.getUser(accessToken);
  if (userError || !userData.user) return respond(401, { error: 'Your session is invalid or expired. Sign in again.' });

  const { data: staffProfile, error: profileError } = await staffClient
    .from('profiles')
    .select('role')
    .eq('auth_user_id', userData.user.id)
    .maybeSingle();
  if (profileError) return respond(500, { error: 'Could not verify Staff access.' });
  if (staffProfile?.role !== 'Staff') return respond(403, { error: 'Only Scholarship Staff can register scholar accounts.' });

  const { data: program, error: programError } = await staffClient
    .from('scholarship_programs')
    .select('id')
    .eq('id', programId)
    .maybeSingle();
  if (programError) return respond(500, { error: 'Could not validate the selected scholarship program.' });
  if (!program) return respond(400, { error: 'Selected scholarship program does not exist.' });

  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: created, error: createError } = await adminClient.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, student_id: studentId },
  });
  if (createError || !created.user) {
    return respond(400, { error: createError?.message || 'Could not create the Auth account.' });
  }

  const { error: assignmentError } = await staffClient.rpc('assign_new_scholar', {
    p_student_id: studentId,
    p_program_id: programId,
  });
  if (assignmentError) {
    const { error: cleanupError } = await staffClient.rpc('cleanup_unassigned_scholar', {
      p_student_id: studentId,
    });
    const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(created.user.id);
    if (cleanupError || deleteUserError) {
      return respond(500, {
        error: 'Account creation could not be completed or fully rolled back. Contact the project administrator before retrying.',
      });
    }
    return respond(400, { error: assignmentError.message });
  }

  return respond(201, { student_id: studentId, email, message: 'Scholar account created and program assigned.' });
});
