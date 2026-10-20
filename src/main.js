import { createClient } from '@supabase/supabase-js';
import './style.css';

const root = document.querySelector('#app');
const env = import.meta.env;
const supabase = env.VITE_SUPABASE_URL && env.VITE_SUPABASE_ANON_KEY
  ? createClient(env.VITE_SUPABASE_URL, env.VITE_SUPABASE_ANON_KEY)
  : null;

const state = {
  session: null,
  profile: null,
  page: 'dashboard',
  selectedId: null,
  notice: '',
  error: '',
  busy: false,
  data: { submissions: [], assignments: [], profiles: [], programs: [], history: [] },
  filter: { year: '2026-2027', semester: '1', search: '', program: '', compliance: '' }
};

const esc = (value = '') => String(value).replace(/[&<>"']/g, (char) => ({
  '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
})[char]);
const formatDate = (value) => value ? new Date(value).toLocaleString() : '—';
const statusClass = (value) => String(value || '').toLowerCase().replaceAll(' ', '-');
const errorText = (error) => error?.message || 'The request failed. Check your connection and try again.';

function setMessage(message = '', isError = false) {
  state.notice = isError ? '' : message;
  state.error = isError ? message : '';
}

async function loadProfile() {
  if (!state.session) {
    state.profile = null;
    render();
    return;
  }
  const { data, error } = await supabase.from('profiles')
    .select('id, auth_user_id, student_id, full_name, role')
    .eq('auth_user_id', state.session.user.id).maybeSingle();
  if (error) throw error;
  state.profile = data;
  render();
  if (data) await loadData();
}

async function loadData() {
  if (!state.profile) return;
  state.busy = true;
  render();
  try {
    const [submissions, assignments, profiles, programs] = await Promise.all([
      supabase.from('semester_submissions').select('*').order('submitted_at', { ascending: false }),
      supabase.from('scholar_assignments').select('*'),
      supabase.from('profiles').select('id, student_id, full_name, role'),
      supabase.from('scholarship_programs').select('*').order('program_name')
    ]);
    for (const result of [submissions, assignments, profiles, programs]) {
      if (result.error) throw result.error;
    }
    state.data = {
      submissions: submissions.data || [],
      assignments: assignments.data || [],
      profiles: profiles.data || [],
      programs: programs.data || [],
      history: []
    };
  } catch (error) {
    setMessage(errorText(error), true);
  } finally {
    state.busy = false;
    render();
  }
}

function header() {
  const staff = state.profile?.role === 'Staff';
  return `<header class="topbar">
    <a class="brand" href="#" data-action="home"><span class="brand-mark">S</span><span>Scholarship Monitor<small>Academic compliance portal</small></span></a>
    ${state.profile ? `<nav aria-label="Main navigation">
      <button data-action="home" class="${state.page === 'dashboard' ? 'active' : ''}">Dashboard</button>
      <button data-action="submissions" class="${state.page === 'submissions' ? 'active' : ''}">${staff ? 'Submissions' : 'My submissions'}</button>
      ${staff ? `<button data-action="register" class="${state.page === 'register' ? 'active' : ''}">Register scholar</button>` : `<button data-action="new" class="${state.page === 'new' ? 'active' : ''}">Submit grades</button>`}
    </nav><div class="account"><span>${esc(state.profile.full_name || state.session.user.email)}</span><button class="quiet-button" data-action="logout">Sign out</button></div>` : ''}
  </header>`;
}

function loginView() {
  return `<main class="auth-wrap"><section class="auth-card">
    <div class="eyebrow">SCHOLARSHIP SERVICES</div><h1>Welcome back</h1>
    <p class="muted">Sign in to review scholarship academic compliance.</p>
    <form id="login-form" class="stack-form">
      <label>Email<input name="email" type="email" autocomplete="username" required /></label>
      <label>Password<input name="password" type="password" autocomplete="current-password" required /></label>
      <button class="primary" type="submit">Sign in</button>
    </form>
    <details class="signup"><summary>Need a Scholar account?</summary>
      <p class="muted small">Public registration creates a Scholar profile only. Scholarship Staff accounts are provisioned by an administrator.</p>
      <form id="signup-form" class="stack-form">
        <label>Full name<input name="full_name" autocomplete="name" required /></label>
        <label>Student ID<input name="student_id" autocomplete="off" required /></label>
        <label>Email<input name="email" type="email" autocomplete="email" required /></label>
        <label>Password<input name="password" type="password" minlength="8" autocomplete="new-password" required /></label>
        <label>Confirm password<input name="confirm_password" type="password" minlength="8" autocomplete="new-password" required /></label>
        <button class="secondary" type="submit">Create Scholar account</button>
      </form>
    </details>
  </section></main>`;
}

function submissionProfile(submission) {
  return state.data.profiles.find((profile) => profile.id === submission.scholar_profile_id);
}
function programForAssignment(assignmentId) {
  const assignment = state.data.assignments.find((row) => row.id === assignmentId);
  return state.data.programs.find((row) => row.id === assignment?.program_id);
}
function filteredSubmissions() {
  const { year, semester, search, program, compliance } = state.filter;
  return state.data.submissions.filter((row) => {
    const profile = submissionProfile(row);
    const assignment = state.data.assignments.find((item) => item.id === row.assignment_id);
    const q = search.trim().toLowerCase();
    return row.academic_year === year
      && String(row.semester) === String(semester)
      && (!q || `${profile?.student_id || ''} ${profile?.full_name || ''}`.toLowerCase().includes(q))
      && (!program || assignment?.program_id === program)
      && (!compliance || row.compliance_result === compliance);
  });
}

function filterControls() {
  return `<div class="filters">
    <label>Academic year<input name="filter-year" value="${esc(state.filter.year)}" aria-label="Academic year filter" /></label>
    <label>Semester<select name="filter-semester"><option value="1" ${state.filter.semester === '1' ? 'selected' : ''}>Semester 1</option><option value="2" ${state.filter.semester === '2' ? 'selected' : ''}>Semester 2</option><option value="Summer" ${state.filter.semester === 'Summer' ? 'selected' : ''}>Summer</option></select></label>
    <label>Search<input name="filter-search" value="${esc(state.filter.search)}" placeholder="Student ID or name" /></label>
    <label>Program<select name="filter-program"><option value="">All programs</option>${state.data.programs.map((p) => `<option value="${p.id}" ${state.filter.program === p.id ? 'selected' : ''}>${esc(p.program_name)}</option>`).join('')}</select></label>
    <label>Compliance<select name="filter-compliance"><option value="">All results</option>${['Not Evaluated', 'Compliant', 'With Deficiency'].map((x) => `<option ${state.filter.compliance === x ? 'selected' : ''}>${x}</option>`).join('')}</select></label>
  </div>`;
}

function submissionRows(rows) {
  if (!rows.length) return `<tr><td colspan="7" class="empty">No submissions match these filters.</td></tr>`;
  return rows.map((row) => {
    const profile = submissionProfile(row);
    const program = programForAssignment(row.assignment_id);
    return `<tr>
      <td><strong>${esc(profile?.student_id || 'Unlinked')}</strong><small>${esc(profile?.full_name || 'Scholar')}</small></td>
      <td>${esc(program?.program_name || '—')}</td><td>${esc(row.gwa)}</td>
      <td><span class="badge ${statusClass(row.verification_status)}">${esc(row.verification_status)}</span></td>
      <td><span class="badge ${statusClass(row.compliance_result)}">${esc(row.compliance_result)}</span></td>
      <td><span class="badge ${statusClass(row.renewal_decision)}">${esc(row.renewal_decision)}</span></td>
      <td><button class="link-button" data-action="detail" data-id="${row.id}">View details</button></td>
    </tr>`;
  }).join('');
}

function dashboardView() {
  const staff = state.profile.role === 'Staff';
  const rows = filteredSubmissions();
  const assignedCount = staff
    ? state.data.assignments.filter((a) => a.award_status === 'Active').length
    : state.data.assignments.filter((a) => a.scholar_profile_id === state.profile.id && a.award_status === 'Active').length;
  const showRows = staff ? rows : rows.filter((row) => row.scholar_profile_id === state.profile.id);
  const metrics = [
    ['Assigned scholars', assignedCount, 'scholars'],
    ['Pending verification', rows.filter((r) => r.verification_status === 'Pending').length, 'submissions'],
    ['Compliant', rows.filter((r) => r.compliance_result === 'Compliant').length, 'submissions'],
    ['With Deficiency', rows.filter((r) => r.compliance_result === 'With Deficiency').length, 'submissions']
  ];
  return `<main class="page">
    <section class="page-heading"><div><div class="eyebrow">${staff ? 'STAFF WORKSPACE' : 'SCHOLAR WORKSPACE'}</div><h1>${staff ? 'Academic compliance overview' : `Hello, ${esc(state.profile.full_name || 'Scholar')}`}</h1><p class="muted">${staff ? 'Monitor submissions, verification, and renewal decisions.' : 'View your scholarship assignment and academic submission status.'}</p></div><button class="secondary" data-action="refresh">Refresh records</button></section>
    <section class="metric-grid">${metrics.map(([name, count, suffix]) => `<article class="metric"><span>${name}</span><strong>${count}</strong><small>${suffix}</small></article>`).join('')}</section>
    <section class="panel overview-card">
      <div><div class="eyebrow">CURRENT REPORTING PERIOD</div><h2>${esc(state.filter.year)} · Semester ${esc(state.filter.semester)}</h2>
      <p class="muted">${staff ? 'Use Submissions to search records, filter by program or result, and review individual cases.' : 'Open My submissions to review your records, verification progress, and compliance results.'}</p></div>
      <div class="overview-actions"><button class="secondary" data-action="submissions">View ${staff ? 'submissions' : 'my submissions'}</button>${!staff ? `<button class="primary" data-action="new">Submit grades</button>` : ''}</div>
    </section>
  </main>`;
}

function submissionsView() {
  const staff = state.profile.role === 'Staff';
  const rows = filteredSubmissions();
  const visibleRows = staff ? rows : rows.filter((row) => row.scholar_profile_id === state.profile.id);
  return `<main class="page">
    <section class="page-heading"><div><div class="eyebrow">${staff ? 'STAFF WORKSPACE' : 'SCHOLAR WORKSPACE'}</div><h1>${staff ? 'Submissions' : 'My submissions'}</h1><p class="muted">${staff ? 'Search, filter, and open scholar submissions.' : 'Review your submitted academic summaries and their current status.'}</p></div>
      ${!staff ? `<button class="primary" data-action="new">New submission</button>` : ''}</section>
    ${filterControls()}
    <section class="panel"><div class="panel-heading"><div><h2>${staff ? 'All scholar records' : 'Your records'}</h2><p class="muted small">Academic year ${esc(state.filter.year)} · Semester ${esc(state.filter.semester)}</p></div></div>
      <div class="table-wrap"><table><thead><tr><th>Scholar</th><th>Program</th><th>GWA</th><th>Verification</th><th>Compliance</th><th>Renewal</th><th></th></tr></thead><tbody>${submissionRows(visibleRows)}</tbody></table></div>
    </section>
  </main>`;
}

function newSubmissionView() {
  const current = state.selectedId ? state.data.submissions.find((row) => row.id === state.selectedId) : null;
  const correcting = current?.verification_status === 'Returned';
  return `<main class="page narrow"><button class="back-button" data-action="home">← Dashboard</button><section class="panel form-panel">
    <div class="eyebrow">${correcting ? 'CORRECTION' : 'ACADEMIC RECORD'}</div><h1>${correcting ? 'Correct and resubmit' : 'Submit semester grades'}</h1>
    <p class="muted">${correcting ? `Return reason: ${esc(current.verification_reason || 'Please review and correct your record.')}` : 'Submit the academic summary and a reference to the grade document.'}</p>
    <form id="submission-form" class="form-grid">
      ${correcting ? `<input type="hidden" name="submission_id" value="${current.id}" />` : ''}
      <label>Academic year<input name="academic_year" value="${esc(current?.academic_year || '2026-2027')}" required /></label>
      <label>Semester<select name="semester"><option value="1" ${current?.semester === '1' ? 'selected' : ''}>1</option><option value="2" ${current?.semester === '2' ? 'selected' : ''}>2</option><option value="Summer" ${current?.semester === 'Summer' ? 'selected' : ''}>Summer</option></select></label>
      <label>GWA<input name="gwa" type="number" min="1" max="5" step="0.01" value="${esc(current?.gwa ?? '')}" required /></label>
      <label>Enrolled units<input name="enrolled_units" type="number" min="0" step="1" value="${esc(current?.enrolled_units ?? '')}" required /></label>
      <label>Failed subjects<input name="failed_count" type="number" min="0" step="1" value="${esc(current?.failed_count ?? 0)}" required /></label>
      <label>Incomplete grades<input name="incomplete_count" type="number" min="0" step="1" value="${esc(current?.incomplete_count ?? 0)}" required /></label>
      <label>Dropped subjects<input name="dropped_count" type="number" min="0" step="1" value="${esc(current?.dropped_count ?? 0)}" required /></label>
      <label class="span-two">Grade-document reference<input name="grade_document_ref" value="${esc(current?.grade_document_ref || '')}" placeholder="Document ID or secure URL" required /></label>
      <div class="span-two"><button class="primary" type="submit">${correcting ? 'Resubmit for verification' : 'Submit for verification'}</button></div>
    </form>
  </section></main>`;
}

function detailView() {
  const row = state.data.submissions.find((item) => item.id === state.selectedId);
  if (!row) return `<main class="page"><section class="panel"><p>Submission not found.</p><button class="secondary" data-action="home">Return to dashboard</button></section></main>`;
  const staff = state.profile.role === 'Staff';
  const profile = submissionProfile(row);
  const program = programForAssignment(row.assignment_id);
  const details = row.policy_check_details || {};
  return `<main class="page">
    <button class="back-button" data-action="home">← Dashboard</button>
    <section class="page-heading"><div><div class="eyebrow">SUBMISSION DETAILS</div><h1>${esc(profile?.student_id || '')} · ${esc(row.academic_year)} / ${esc(row.semester)}</h1><p class="muted">${esc(profile?.full_name || '')} · ${esc(program?.program_name || '')}</p></div>
      ${!staff && row.verification_status === 'Returned' ? `<button class="primary" data-action="correct" data-id="${row.id}">Correct submission</button>` : ''}
    </section>
    <section class="detail-grid"><article class="panel"><h2>Academic summary</h2><dl>
      <dt>GWA</dt><dd>${esc(row.gwa)}</dd><dt>Enrolled units</dt><dd>${esc(row.enrolled_units)}</dd><dt>Failed / Incomplete / Dropped</dt><dd>${esc(row.failed_count)} / ${esc(row.incomplete_count)} / ${esc(row.dropped_count)}</dd>
      <dt>Document reference</dt><dd class="break">${esc(row.grade_document_ref || '—')}</dd><dt>Submitted</dt><dd>${esc(formatDate(row.submitted_at))}</dd>
    </dl></article><article class="panel"><h2>Workflow status</h2><dl>
      <dt>Verification</dt><dd><span class="badge ${statusClass(row.verification_status)}">${esc(row.verification_status)}</span></dd><dt>Verification note</dt><dd>${esc(row.verification_reason || '—')}</dd>
      <dt>Compliance</dt><dd><span class="badge ${statusClass(row.compliance_result)}">${esc(row.compliance_result)}</span></dd>
      <dt>Renewal</dt><dd><span class="badge ${statusClass(row.renewal_decision)}">${esc(row.renewal_decision)}</span></dd><dt>Decision notes</dt><dd>${esc(row.decision_notes || '—')}</dd>
    </dl></article></section>
    <section class="panel"><h2>Policy checks</h2>${details.checks?.length ? `<div class="checks">${details.checks.map((check) => `<div class="check-row"><span class="${check.pass ? 'pass' : 'fail'}">${check.pass ? '✓' : '!'}</span><div><strong>${esc(check.label)}</strong><small>Actual: ${esc(check.actual)} · Policy: ${esc(check.threshold)}</small></div></div>`).join('')}</div>` : '<p class="muted">Evaluation has not been completed.</p>'}
      ${Array.isArray(row.compliance_reasons) && row.compliance_reasons.length ? `<ul class="reason-list">${row.compliance_reasons.map((reason) => `<li>${esc(reason)}</li>`).join('')}</ul>` : ''}
    </section>
    ${staff ? `<section class="panel"><h2>Staff actions</h2><div class="action-grid">
      <form id="verify-form"><label>Verification action<select name="status"><option value="Verified">Verify evidence</option><option value="Returned">Return for correction</option></select></label><label>Reason (required when returned)<textarea name="reason" rows="2"></textarea></label><button class="secondary" type="submit">Save verification</button></form>
      <div><p class="muted small">Evaluation is allowed only after evidence is verified.</p><button class="primary" data-action="evaluate" data-id="${row.id}">Evaluate compliance</button></div>
      <form id="decision-form"><label>Renewal decision<select name="decision"><option value="Approved">Approve renewal</option><option value="Held">Hold renewal</option></select></label><label>Decision notes / hold reason<textarea name="notes" rows="2"></textarea></label><button class="secondary" type="submit">Record decision</button></form>
    </div></section>` : ''}
    <section class="panel"><h2>History</h2><div id="history-content" class="muted">Loading history…</div></section>
  </main>`;
}

function registerView() {
  return `<main class="page narrow"><button class="back-button" data-action="home">← Dashboard</button><section class="panel form-panel">
    <div class="eyebrow">STAFF WORKSPACE</div><h1>Register a scholar</h1><p class="muted">Create a Scholar login and assign a program. Share the temporary password privately and ask the student to change it after signing in.</p>
    <form id="register-form" class="stack-form">
      <label>Student ID<input name="student_id" autocomplete="off" required /></label>
      <label>Email<input name="email" type="email" autocomplete="off" required /></label>
      <label>Full name<input name="full_name" autocomplete="name" required /></label>
      <label>Temporary password<input name="temporary_password" type="password" minlength="8" autocomplete="new-password" required /></label>
      <label>Confirm temporary password<input name="confirm_password" type="password" minlength="8" autocomplete="new-password" required /></label>
      <label>Scholarship program<select name="program_id" required><option value="">Select program</option>${state.data.programs.map((p) => `<option value="${p.id}">${esc(p.program_name)}</option>`).join('')}</select></label>
      <button class="primary" type="submit">Create account and assign program</button>
    </form>
  </section></main>`;
}

function render() {
  if (!supabase) {
    root.innerHTML = `<main class="auth-wrap"><section class="auth-card"><h1>Configuration required</h1><p class="muted">Create a local <code>.env</code> file using <code>.env.example</code>, then restart the development server.</p></section></main>`;
    return;
  }
  root.innerHTML = `${header()}${state.error ? `<div class="alert error" role="alert">${esc(state.error)}</div>` : ''}${state.notice ? `<div class="alert success" role="status">${esc(state.notice)}</div>` : ''}
    ${state.busy ? '<main class="page"><div class="loading">Loading records…</div></main>' : !state.session ? loginView()
      : !state.profile ? `<main class="page"><section class="panel"><h1>Profile setup required</h1><p class="muted">Your Auth account does not have a Scholar or Staff profile. Ask an administrator to provision the account.</p></section></main>`
        : state.page === 'detail' ? detailView()
          : state.page === 'new' ? newSubmissionView()
            : state.page === 'register' ? registerView()
              : state.page === 'submissions' ? submissionsView()
              : dashboardView()}`;
  if (state.page === 'detail' && state.selectedId) loadHistory(state.selectedId);
}

async function loadHistory(id) {
  const target = document.querySelector('#history-content');
  if (!target) return;
  const { data, error } = await supabase.from('submission_history')
    .select('action_type, old_values, new_values, notes, acting_user_id, created_at')
    .eq('submission_id', id).order('created_at', { ascending: false });
  if (error) {
    target.textContent = `Could not load history: ${errorText(error)}`;
    return;
  }
  target.innerHTML = data?.length ? `<ol class="history-list">${data.map((entry) => `<li><strong>${esc(entry.action_type.replaceAll('_', ' '))}</strong><small>${esc(formatDate(entry.created_at))}${entry.acting_user_id ? ` · Actor ${esc(entry.acting_user_id)}` : ''}${entry.notes ? ` · ${esc(entry.notes)}` : ''}</small></li>`).join('')}</ol>` : 'No history entries.';
}

async function runAction({ action, id }) {
  setMessage();
  try {
    if (action === 'logout') {
      const { error } = await supabase.auth.signOut();
      if (error) throw error;
      return;
    }
    if (action === 'home') {
      state.page = 'dashboard'; state.selectedId = null;
    } else if (action === 'new') {
      state.selectedId = null; state.page = 'new';
    } else if (action === 'submissions') {
      state.page = 'submissions';
    } else if (action === 'register') {
      state.page = 'register';
    } else if (action === 'detail') {
      state.selectedId = id;
      state.page = 'detail';
    } else if (action === 'correct') {
      state.selectedId = id; state.page = 'new';
    } else if (action === 'refresh') {
      await loadData();
      setMessage('Records refreshed.');
    } else if (action === 'evaluate') {
      const { error } = await supabase.rpc('evaluate_submission', { p_submission_id: id });
      if (error) throw error;
      setMessage('Compliance evaluation completed.');
      await loadData();
      state.page = 'detail';
    }
  } catch (error) {
    setMessage(errorText(error), true);
  }
  render();
}

root.addEventListener('click', async (event) => {
  const button = event.target.closest('[data-action]');
  if (!button) return;
  event.preventDefault();
  await runAction({ action: button.dataset.action, id: button.dataset.id });
});

root.addEventListener('change', (event) => {
  const mapping = { 'filter-semester': 'semester', 'filter-program': 'program', 'filter-compliance': 'compliance' };
  if (mapping[event.target.name]) {
    state.filter[mapping[event.target.name]] = event.target.value;
    render();
  } else if (event.target.name === 'filter-search' || event.target.name === 'filter-year') {
    state.filter[event.target.name === 'filter-search' ? 'search' : 'year'] = event.target.value;
    render();
  }
});

root.addEventListener('submit', async (event) => {
  event.preventDefault();
  const form = event.target;
  const values = Object.fromEntries(new FormData(form).entries());
  setMessage();
  try {
    if (form.id === 'login-form') {
      const { error } = await supabase.auth.signInWithPassword({ email: values.email, password: values.password });
      if (error) throw error;
    } else if (form.id === 'signup-form') {
      if (values.password !== values.confirm_password) {
        throw new Error('Password and confirmation do not match.');
      }
      const { data, error } = await supabase.auth.signUp({
        email: values.email, password: values.password,
        options: { data: { full_name: values.full_name, student_id: values.student_id.trim() } }
      });
      if (error) throw error;
      if (!data.session) setMessage('Account created. Confirm your email if required, then sign in.');
      else setMessage('Scholar account created.');
    } else if (form.id === 'submission-form') {
      const correcting = Boolean(values.submission_id);
      const rpc = correcting ? 'resubmit_returned_submission' : 'submit_semester_submission';
      const args = {
        p_academic_year: values.academic_year,
        p_semester: values.semester,
        p_gwa: Number(values.gwa),
        p_enrolled_units: Number(values.enrolled_units),
        p_failed_count: Number(values.failed_count),
        p_incomplete_count: Number(values.incomplete_count),
        p_dropped_count: Number(values.dropped_count),
        p_grade_document_ref: values.grade_document_ref
      };
      if (correcting) args.p_submission_id = values.submission_id;
      const { error } = await supabase.rpc(rpc, args);
      if (error?.code === '23505') throw new Error('A submission already exists for this academic year and semester.');
      if (error) throw error;
      setMessage(correcting ? 'Corrected record resubmitted for verification.' : 'Submission received and queued for verification.');
      state.page = 'dashboard'; state.selectedId = null;
      await loadData();
    } else if (form.id === 'verify-form') {
      const { error } = await supabase.rpc('set_submission_verification', {
        p_submission_id: state.selectedId, p_status: values.status, p_reason: values.reason
      });
      if (error) throw error;
      setMessage('Verification status saved.');
      await loadData();
    } else if (form.id === 'decision-form') {
      const { error } = await supabase.rpc('decide_renewal', {
        p_submission_id: state.selectedId, p_decision: values.decision, p_notes: values.notes
      });
      if (error) throw error;
      setMessage('Renewal decision recorded.');
      await loadData();
    } else if (form.id === 'register-form') {
      if (values.temporary_password !== values.confirm_password) {
        throw new Error('Temporary password and confirmation do not match.');
      }
      const { data, error } = await supabase.functions.invoke('create-scholar', {
        body: {
          student_id: values.student_id.trim(),
          email: values.email.trim(),
          full_name: values.full_name.trim(),
          temporary_password: values.temporary_password,
          program_id: values.program_id
        }
      });
      if (error) {
        let message = errorText(error);
        if (error.context instanceof Response) {
          const responseBody = await error.context.json().catch(() => null);
          if (responseBody?.error) message = responseBody.error;
        }
        throw new Error(message);
      }
      if (data?.error) throw new Error(data.error);
      setMessage(`Scholar account ${data.email} created and assigned. Share the temporary password privately.`);
      form.reset(); await loadData();
    }
  } catch (error) {
    setMessage(errorText(error), true);
  }
  render();
});

supabase?.auth.onAuthStateChange((_event, session) => {
  state.session = session;
  setMessage();
  queueMicrotask(() => loadProfile().catch((error) => {
    setMessage(errorText(error), true);
    render();
  }));
});

if (supabase) {
  supabase.auth.getSession().then(({ data, error }) => {
    if (error) setMessage(errorText(error), true);
    state.session = data?.session || null;
    return loadProfile();
  }).catch((error) => {
    setMessage(errorText(error), true);
    render();
  });
}
render();
