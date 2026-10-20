# Student Scholarship Monitoring and Academic Compliance System

This is a local-first web application using HTML, CSS, vanilla JavaScript ES modules, Vite, Supabase Auth, and PostgreSQL. The Dashboard is an overview; Submissions is the searchable record list. It uses synthetic scholar data only. The Registrar remains the source of official grades; this app stores submitted summaries and document references and does not release payments.

## Project structure

- `index.html`, `src/main.js`, `src/style.css` — responsive browser interface.
- `supabase/migrations/202610200001_initial_schema.sql` — schema, constraints, RLS, and protected workflow functions.
- `supabase/functions/create-scholar/index.ts` — Staff-only server-side Auth account creation and program assignment.
- `supabase/seed.sql` — two policies and six synthetic scholars/submissions; safe to re-run.
- `.env.example` — public browser configuration placeholders.

## Supabase setup

1. Create a Supabase project. Never put a service-role key in this application or in a committed file.
2. In the Supabase SQL Editor, run each migration **once only**, in order: `supabase/migrations/202610200001_initial_schema.sql`, `supabase/migrations/202610200002_signup_student_id.sql`, and `supabase/migrations/202610200003_staff_create_scholar.sql`, then run `supabase/seed.sql`. Do not rerun an already-applied migration; the initial schema migration creates enum types and tables and is not a repeatable seed. If earlier migrations were already applied, run only the migration files not yet applied. Alternatively, use the Supabase CLI `supabase db push` after linking a project.
3. In Authentication settings, configure the email provider. For a private local demo, email confirmation may be disabled; otherwise use the confirmation link sent by Supabase.
4. Create a staff test account using Supabase Dashboard → Authentication → Users. Then, as the project administrator, set its profile to Staff:

   ```sql
   update public.profiles
   set role = 'Staff', full_name = 'Synthetic Staff'
   where auth_user_id = '<staff-auth-user-uuid>';
   ```

   The UUID above is found in the Auth Users dashboard. Do not promote a user from the app; public signup always creates Scholar profiles. Applying `202610200002_signup_student_id.sql` ensures signup student IDs are stored in `profiles`.
5. Apply the database migrations above, then deploy the server-side account provisioning function. Install/use the Supabase CLI, sign in, link this project, then deploy:

   ```sh
   npx supabase login
   npx supabase link --project-ref pyjwubodytgzgqtyosqi
   npx supabase functions deploy create-scholar
   ```

   The Edge Function uses Supabase-managed `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` server-side. Never put the service-role key in `.env`, Vite, or browser code. `Failed to send a request to the Edge Function` usually means the function has not been deployed yet, the project URL in `.env` is wrong, or network access is blocked. After deployment, refresh the app and sign in again before retrying.
6. Copy `.env.example` to `.env` and set:
   - `VITE_SUPABASE_URL` — project URL.
   - `VITE_SUPABASE_ANON_KEY` — publishable/anon key only.
7. Install and run:

   ```sh
   npm install
   npm run dev
   ```

   Use the local URL printed by Vite. To make a production bundle, run `npm run build`; optionally deploy `dist/` to any static host and configure the same public environment values at build time.

## Deploy to GitHub Pages

The workflow in `.github/workflows/deploy-pages.yml` builds and deploys the Vite app whenever changes are pushed to `main`.

1. Create a GitHub repository and push this project to its `main` branch. `.env` is excluded by `.gitignore`; never commit a service-role key or other server secret.
2. In the repository, add the Actions **variables** `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` under **Settings → Secrets and variables → Actions → Variables**. These are browser-facing Supabase project configuration values, not service-role credentials. The workflow uses them at build time.
3. In **Settings → Pages**, select **GitHub Actions** as the build and deployment source. The workflow publishes the `dist/` artifact.
4. Wait for the `Deploy to GitHub Pages` workflow to succeed. The public URL is shown in the workflow's deployment environment.
5. In the Supabase Dashboard, set the deployed Pages URL as the Auth **Site URL** and add it to the allowed redirect URLs. Confirm that the migrations and `create-scholar` Edge Function have been deployed to the same Supabase project. Keep `SUPABASE_SERVICE_ROLE_KEY` server-side in Supabase only.

The site is publicly accessible when the repository is public. GitHub Pages availability for private repositories depends on the GitHub plan. A successful static-site deployment does not by itself confirm that Supabase migrations, Auth redirect settings, or the Edge Function are ready.

## Data, workflows, and security

Policies are stored in `scholarship_programs`; evaluation reads the assigned program row and captures its thresholds and deadline in `policy_check_details` and history. The seed deadline is `2026-10-30 17:00:00+08` (Asia/Manila). An exact deadline timestamp passes; only a strictly later timestamp fails.

Normal submissions receive `now()` from PostgreSQL. Seed timestamps are explicit historical/demo timestamps in the SQL seed. RLS restricts profile, assignment, submission, and history reads to the owning Scholar or Staff. Direct client writes are not granted. Security-definer functions use an empty search path, check the caller's role/ownership, enforce transitions, and write history in the same transaction. History is read-only to application roles. The award status is independent of compliance and renewal.

The browser never treats local storage as the system of record. It uses parameterized Supabase queries/RPCs, escapes displayed user-controlled strings, and reports database errors in the interface. Staff scholar registration collects student ID, email, full name, temporary password, password confirmation, and scholarship program. It invokes the `create-scholar` Edge Function, which validates the Staff JWT, creates a confirmed Auth account server-side, and assigns the Scholar profile through a protected database function. Passwords are not stored in the app database or returned by the function. Staff should share temporary passwords privately and ask Scholars to change them after signing in. The client-facing legacy registration/link RPC grants are revoked by migration `202610200003`.

To link a test Auth user to a seeded Scholar, a project administrator can use `public.link_scholar_auth_user` in the SQL Editor:

```sql
select public.link_scholar_auth_user('A01', '<scholar-auth-user-uuid>');
```

## Test cases TC01–TC10

No authenticated Staff/Scholar sessions or hosted database/API test access were available in this workspace. Therefore hosted database/API execution results are **Not Run**, not presumed passes. The seed data has the expected baseline values, but that is not a substitute for executing the workflow tests. Run tests against a disposable Supabase project and reset the seed before each mutating case.

| Test ID | Input/action | Expected result | Actual result | Status | Evidence reference |
|---|---|---|---|---|---|
| TC01 | Staff evaluates A01 (1.75 GWA, exactly at deadline) | Compliant; boundary passes | Not run; Supabase credentials unavailable | Not Run | `supabase/seed.sql` A01 fixture; evaluate via submission detail |
| TC02 | Staff evaluates A02 (GWA 1.76) | With Deficiency; GWA reason | Not run; Supabase credentials unavailable | Not Run | `supabase/seed.sql` A02 fixture |
| TC03 | Staff evaluates A03 (Community Scholar, one drop) | Compliant; one dropped subject allowed | Not run; Supabase credentials unavailable | Not Run | `supabase/seed.sql` A03 fixture |
| TC04 | Staff evaluates A04 (14 units, one incomplete) | With Deficiency; both reasons shown | Not run; Supabase credentials unavailable | Not Run | `supabase/seed.sql` A04 fixture |
| TC05 | Staff evaluates A05 (one failure, one minute late) | With Deficiency; failure and deadline reasons | Not run; Supabase credentials unavailable | Not Run | `supabase/seed.sql` A05 fixture |
| TC06 | Evaluate and approve A06 before verification | Both operations rejected | Not run; Supabase credentials unavailable | Not Run | `evaluate_submission` and `decide_renewal` functions in migration |
| TC07 | Duplicate semester; GWA 0.50; negative count | Duplicate and CHECK constraint errors; no invalid row | Not run; Supabase credentials unavailable | Not Run | unique/check constraints in migration |
| TC08 | Scholar queries another scholar and calls verification RPC | No other scholar data returned; mutation denied | Not run; two Auth sessions required | Not Run | RLS policies and `set_submission_verification` in migration |
| TC09 | Staff returns record; owner corrects and resubmits; refresh | Pending verification; stale outcomes cleared; history retained | Not run; two Auth sessions required | Not Run | `resubmit_returned_submission` and history policy |
| TC10 | Staff approves compliant, holds deficient; Scholar attempts decision | Valid Staff decisions persist; Scholar mutation denied | Not run; two Auth sessions required | Not Run | `decide_renewal` function in migration |

### Reproducing the cases

- A01–A05 are seeded with the requested expected baseline results and renewal `Undecided`. From the Staff detail screen, re-evaluate A01–A05 to exercise database policy evaluation.
- A06 is Pending. The staff evaluation and decision RPCs must reject it before verification/evaluation.
- For TC07, use a Scholar account linked to a seeded profile and submit the same year/semester twice; separately submit GWA `0.50` and a negative count. Expect Postgres validation errors and verify the unique row count did not increase.
- For TC08/TC10, sign in as a Scholar and issue direct Supabase requests (not UI clicks): select `semester_submissions` for a different profile's submission UUID; invoke `set_submission_verification` and `decide_renewal`. RLS should return no foreign row and the protected calls must fail authorization.
- For TC09, as Staff return A01 with a correction reason, sign in as its linked Scholar to correct/resubmit, refresh, and inspect its history. Re-run `supabase/seed.sql` only on a disposable test project; the seed resets the six baseline submissions.
- Each mutating case should use a separate disposable/reset fixture. Keep credentials in local environment or the Supabase dashboard, never in source, screenshots, or committed files.

## Known limitations

- Evidence is a document reference/URL; file upload/storage and evidence contents are out of scope.
- There is no Registrar integration, SMS, machine learning, payment handling, exceptions, or formal appeal workflow.
- Staff accounts and existing Auth users are provisioned/linked administratively; there is no in-app privileged Auth-user creation.
- The test matrix is documented but has not been executed against a live Supabase project in this environment.
#   S A D _ E x a m _ S e c t i o n _ A _ M - 0 0 6 6 7 1  
 