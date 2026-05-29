# My Project — Food Map + Nutrition Tracker

Two web apps that share an aesthetic, soon to share a backend.

- **Food map** ([public/index.html](public/index.html)) — a Leaflet map of curated 重庆 / 四川 / etc. food spots. Data in [public/food-data.js](public/food-data.js).
- **Nutrition tracker** ([public/tracker.html](public/tracker.html)) — daily intake + body comp + workout + weekly review, currently localStorage-only.

## Layout

```
.
├── public/                       # static site, deployed to Cloudflare Pages
│   ├── index.html                # food map
│   ├── tracker.html              # nutrition tracker
│   ├── food-data.js              # food-map dataset
│   └── chongqing-food-map.html   # legacy redirect (kept so old links don't break)
├── supabase/
│   ├── migrations/
│   │   └── 0001_init.sql         # tracker DB schema + RLS + updated_at trigger
│   └── functions/
│       └── v1_usda_search/       # Edge Function: USDA FoodData Central proxy + cache
│           └── index.ts
└── .github/workflows/
    └── backup.yml                # monthly pg_dump → workflow artifact
```

## Architecture (in-flight migration)

| Layer | Today | Target |
|---|---|---|
| Frontend hosting | local Python http.server | Cloudflare Pages (free, served at `<project>.pages.dev`) |
| Storage | `localStorage` only | Supabase Postgres (free until ~40 MAU, then $25/mo) |
| Auth | none (single-user implicit) | Supabase Auth — email magic-link |
| USDA API | client-side fetch, key in browser | Supabase Edge Function with server-side key + 90-day cache |
| Mobile (future) | n/a | Capacitor wrap of the same `public/` — same backend, ~95% code reuse |

Full migration plan: `/Users/cam/.claude/plans/ok-for-now-how-stateful-meteor.md`.

### Mobile-readiness baked in

- Every user-data table has `updated_at` + `deleted_at` from day 1 → enables future delta sync without schema migrations.
- IDs are client-generated UUIDs → offline-created rows on mobile won't collide on sync.
- All storage goes through a `repo` object in `tracker.html` → swapping backends (or adding offline-first sync) is a one-place change.
- USDA proxy + cache live server-side → mobile inherits both for free.

## Running locally (current state)

```sh
# from the project root
python3 -m http.server 8765
# then open http://localhost:8765/public/tracker.html
#       or http://localhost:8765/public/index.html
```

The tracker stores everything in browser `localStorage` until Steps 3–5 of the migration land.

## Migration status

- [x] **Step 0** — restructure into `public/` + skeleton dirs
- [x] **Step 1** — Supabase schema + RLS migration written (not yet applied to a project)
- [x] **Step 2** — repo layer over localStorage (no behavior change)
- [ ] **Step 3** — Supabase Auth + magic-link sign-in (needs Supabase project)
- [ ] **Step 4** — swap profile/weight/workouts repo bodies to Supabase
- [ ] **Step 5** — swap meal entries repo body to Supabase
- [x] **Step 6 (artifact)** — Edge Function written (not yet deployed)
- [ ] **Step 7** — deploy `public/` to Cloudflare Pages
- [x] **Step 8 (artifact)** — backup workflow written (needs `SUPABASE_DB_URL` secret in GitHub)
