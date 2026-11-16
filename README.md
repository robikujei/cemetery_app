# cemetery_app

A new Flutter project.

## Deploy to Vercel

From this directory in PowerShell, sign in once:

```powershell
npx --yes vercel@latest login
```

Build and publish the non-admin production deployment from its linked Vercel
project directory:

```powershell
.\tools\deploy_vercel.ps1 -Audience users
```

Build and publish the separate admin deployment after linking this checkout to
the admin Vercel project:

```powershell
.\tools\deploy_vercel.ps1 -Audience admin
```

The `admin` build accepts only the `admin` role and exposes the administrator
route. The `users` build accepts visitor, lot-owner, and gate-officer roles and
does not include the administrator route. Because `.vercel/project.json` can
point to only one project at a time, verify the linked project with
`Get-Content .vercel/project.json` before each production deployment, or use
separate clean checkouts for the two Vercel projects.

Use `-Preview` for a preview deployment. On the first deployment, select your
Vercel account and create or link the intended project. Subsequent deployments
reuse the local `.vercel` project link.

The script requires Flutter and Node.js on PATH. It builds locally, then uploads
`build/web`; Vercel does not install Flutter or run a build. Always rebuild before
deploying. This configuration is for local CLI deployments, not automatic builds
from Git. Supabase remains the backend; deployment does not execute SQL imports.

If email confirmation or password-reset redirects are enabled, configure the
production URL in Supabase Authentication's URL settings as appropriate.

Vercel CLI reference: https://vercel.com/docs/cli/deploy

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
