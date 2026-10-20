# Scholarship Monitor

A web application for scholarship academic-submission tracking and compliance review. It uses vanilla JavaScript, Vite, Supabase Auth, and PostgreSQL.

The application stores Scholar-submitted academic summaries and evidence references. The Registrar remains the source of official grades. The application does not process payments.

## Features

- Scholar and Staff roles with protected access.
- Semester grade-summary submission and correction workflow.
- Evidence-reference verification, policy-based compliance evaluation, and separate renewal decisions.
- Searchable submissions, dashboard summaries, and action history.
- Supabase row-level security and database-enforced workflow operations.

## Project files

- `index.html`, `src/main.js`, `src/style.css` — browser application.
- `supabase/migrations/` — database schema, access policies, and workflow functions. Apply migrations once, in filename order.
- `supabase/functions/create-scholar/` — Staff-only Scholar account provisioning function.
- `supabase/seed.sql` — two example policies and six synthetic Scholar submissions.
- `ANALYSIS.md` — requirements and design baseline.

## Supabase setup

1. Create a Supabase project and configure the email provider under **Authentication**.
2. Apply each migration in `supabase/migrations/` once, in filename order. Then run `supabase/seed.sql` if you want the synthetic demo records. Do not rerun migrations that have already been applied.
3. Create a Staff test account under **Authentication → Users**. As the project administrator, promote its profile:

   ```sql
   update public.profiles
   set role = 'Staff', full_name = 'Synthetic Staff'
   where auth_user_id = '<staff-auth-user-uuid>';
   ```

   Replace the placeholder with the Auth user's UUID. Public signup creates Scholar profiles only.
4. Deploy the `create-scholar` Edge Function. It uses Supabase-managed `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` on the server:

   ```sh
   npx supabase login
   npx supabase link --project-ref YOUR_PROJECT_REF
   npx supabase functions deploy create-scholar
   ```
5. Create a local `.env` file from `.env.example` and set:

   ```dotenv
   VITE_SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
   VITE_SUPABASE_ANON_KEY=YOUR_PUBLISHABLE_OR_ANON_KEY
   ```

   Use only a publishable/anon key in the browser. Never put a service-role key in `.env`, browser code, or Git.
6. Install dependencies and start the development server:

   ```sh
   npm install
   npm run dev
   ```

## Deploy to GitHub Pages

This project publishes the built static files from the repository's `main` branch root. The local `.env` file is not uploaded; Vite embeds the browser-facing Supabase URL and publishable/anon key into the generated JavaScript bundle during the build.

1. Create `.env` from `.env.example` and set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Only use the public publishable/anon key; never use or publish a service-role key.
2. Build the files that GitHub Pages serves:

   ```sh
   npm run build:pages
   ```

   This builds the app and copies the generated HTML and hashed assets into the repository root and `assets/`.
3. Commit and push the changed `index.html` and new files under `assets/` to `main`.
4. In the repository, open **Settings → Pages** and select **Deploy from a branch**, branch **main**, folder **/(root)**.
5. In Supabase **Authentication → URL Configuration**, set the Pages URL as the Site URL and add it to the allowed redirect URLs. Confirm that the database migrations and `create-scholar` Edge Function are deployed to the same Supabase project.

The site is publicly accessible from this public repository. A successful Pages publish confirms that static files were served; it does not verify Supabase configuration or connectivity.

## Workflow and data notes

- Evaluation uses the policy associated with the Scholar's program assignment and stores a snapshot of the thresholds used.
- A submission at the exact deadline passes; a submission after it fails the deadline check.
- Verification, compliance, renewal decision, and scholarship award status are separate. A deficiency does not automatically change the award status.
- The application stores a document reference, not uploaded files. It does not integrate with the Registrar, process payments, or provide appeals or policy exceptions.
- Staff and existing Auth accounts are provisioned administratively; privileged account creation is not available to public users.

## Test cases

The following cases describe expected results. Hosted database/API tests were not run in the development workspace, so these are **not test pass claims**. Use a disposable Supabase project for mutating tests.

| ID | Scenario | Expected result |
| --- | --- | --- |
| TC01 | Evaluate A01 at the deadline with passing values | Compliant; exact deadline passes. |
| TC02 | Evaluate A02 with GWA 1.76 | With Deficiency; GWA reason is shown. |
| TC03 | Evaluate A03 with one allowed drop | Compliant. |
| TC04 | Evaluate A04 with 14 units and one incomplete | With Deficiency; both reasons are shown. |
| TC05 | Evaluate A05 with one failure and a late submission | With Deficiency; failure and deadline reasons are shown. |
| TC06 | Evaluate or approve pending A06 | Both actions are rejected before verification/evaluation. |
| TC07 | Submit a duplicate period, GWA 0.50, or a negative count | Duplicate/invalid values are rejected; no invalid row is stored. |
| TC08 | Scholar requests another Scholar's record or calls a Staff-only verification action | No foreign record is returned; the unauthorized mutation is rejected. |
| TC09 | Staff returns a record; its owner corrects and resubmits | Status returns to Pending / Not Evaluated / Undecided and prior history remains. |
| TC10 | Staff decides renewal; Scholar attempts the same action | Authorized Staff decisions persist; Scholar decision is rejected. |

Seed records A01–A06 are in `supabase/seed.sql`. Reset only a disposable test project before repeating mutating scenarios. Never include credentials in test data, screenshots, or committed files.
