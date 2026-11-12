# Ikram Flutter browser

Corrected Flutter source for the uploaded Arabic browser, maintained in
`flutter/ikram_browser`. Preserve Flutter; this request is to fix the supplied
code, not convert it into a web or Expo app.

## Run & Operate

- `dart flutter/ikram_browser/tool/check_domain.dart` — dependency-free domain checks
- `dart analyze flutter/ikram_browser/lib/domain.dart flutter/ikram_browser/tool/check_domain.dart` — analyze the pure Dart logic
- Full Flutter commands and native platform requirements are in `flutter/ikram_browser/README.md`.
- Flutter is not installed here. The Dart SDK can validate pure logic and parse
  source, but cannot verify the Flutter widgets or native WebView integration.
- No new runnable preview was created for this source-only repair.
- The pnpm packages below are the supplied template, not the Flutter app.

- `pnpm --filter @workspace/api-server run dev` — run the API server (port 5000)
- `pnpm run typecheck` — full typecheck across all packages
- `pnpm run build` — typecheck + build all packages
- `pnpm --filter @workspace/api-spec run codegen` — regenerate API hooks and Zod schemas from the OpenAPI spec
- `pnpm --filter @workspace/db run push` — push DB schema changes (dev only)
- Required env: `DATABASE_URL` — Postgres connection string

## Stack

- pnpm workspaces, Node.js 24, TypeScript 5.9
- API: Express 5
- DB: PostgreSQL + Drizzle ORM
- Validation: Zod (`zod/v4`), `drizzle-zod`
- API codegen: Orval (from OpenAPI spec)
- Build: esbuild (CJS bundle)

## Where things live

_Populate as you build — short repo map plus pointers to the source-of-truth file for DB schema, API contracts, theme files, etc._

## Architecture decisions

- Do not approximate native browser privacy with an iframe or server-side proxy.
  The repair keeps the original Flutter platform instead.
- Do not claim isolated browser profiles: the supplied plugin's storage is shared.
  Actual persistent isolation would require a separate native architecture.
- Do not add incognito as a substitute for isolation: Android's plugin implementation
  clears all WebView cookies when incognito is enabled.

## Product

_Describe the high-level user-facing capabilities of this app once they exist._

## User preferences

_Populate as you build — explicit user instructions worth remembering across sessions._

## Gotchas

_Populate as you build — sharp edges, "always run X before Y" rules._

## Pointers

- See the `pnpm-workspace` skill for workspace structure, TypeScript setup, and package details
