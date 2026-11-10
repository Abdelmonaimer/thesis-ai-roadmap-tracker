# Thesis AI Roadmap Tracker

A single-user progress tracker based on the supplied Thesis AI Roadmap. It preserves the seven stages and four tracks, and adds password-protected per-step status and notes, cloud saving, and portable backups.

## Stack

- Static HTML and JavaScript for the roadmap UI.
- Vercel Node.js Function for sign-in and saving progress.
- Neon Postgres, provisioned through the Vercel Marketplace, for durable cloud storage.

The database table is created automatically the first time the app connects. The schema is also in `database/schema.sql`.

## Deploy to Vercel

1. Put this `thesis-roadmap-app` folder in a private GitHub repository and import it into Vercel. If you import the parent repository, set the Vercel **Root Directory** to `thesis-roadmap-app`.
2. In Vercel, open **Storage → Marketplace**, install Neon, create a Postgres database, and connect it to this project. The integration adds `DATABASE_URL` to the project.
3. In **Project Settings → Environment Variables**, add:
   - `APP_PASSWORD`: a long private password you will use to open the roadmap.
   - `SESSION_SECRET`: a random secret with at least 32 characters. Generate one with `openssl rand -base64 32` or a password manager.
4. Redeploy after adding the environment variables.

Vercel's [Hobby plan](https://vercel.com/docs/plans/hobby) is free for personal projects. Vercel's own Postgres product has been retired; the [Marketplace](https://vercel.com/docs/marketplace-storage) connects this app to Neon, whose [Free plan](https://neon.com/pricing) currently includes 100 CU-hours and 1 GB of Postgres storage per project. Free plan quotas and terms can change; keep periodic backups using **Export backup** in the app.

## Run locally

1. Install Node.js and run `npm install` in this folder.
2. Copy `.env.example` to `.env.local` and fill in `DATABASE_URL`, `APP_PASSWORD`, and `SESSION_SECRET`. You can pull the Vercel database URL with `npx vercel env pull .env.local` after linking the project.
3. Run `npm run dev` and open the local URL shown by Vercel CLI.

## Progress and backups

- Every task and stage gate has **Not started**, **In progress**, and **Finished** states.
- Use each task's **My work notes** area to record what you did, your next step, or a blocker.
- Changes save to Postgres automatically. The status indicator shows when cloud saving is pending or unavailable.
- **Export backup** downloads all statuses and notes as JSON. **Import backup** merges a previously exported file into the current progress.
- The browser also keeps a local recovery copy. It does not replace the database.
- The roadmap outline is included in the static page; the password protects saved progress and notes.

This is a private one-password workspace. It does not provide separate user accounts or a public registration flow.
