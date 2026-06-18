# Sovereign Portal — Code-Stripping Checklist

**Purpose.** Move the eight private repos under `github.com/freshifyv2/*` to public repos under `github.com/sovereign-portal/*` without leaking Freshify branding, customer data, infrastructure identifiers, or anything else that doesn't belong in a public reference implementation.

**Scope.** This document covers the mechanical strip-and-rename work. It does not cover documentation (already done — see the six public docs in the Freshify space) or meta files (already done — see `sovereign-portal-meta/`).

**Audience.** Timothy Baio and Krish Michaels. Internal Freshify document — do not publish.

**Last updated.** June 2026 — reconciled against the RAS Users / Customers / Workspaces redesign. Four reference module types stand: **Shell + Users (BE/FE) + Customers (BE/FE) + Workspaces (BE/FE)**. The Registration / Login work that used to live in a separate RLG module is folded into the **Users module**, owning identity end-to-end. There is no fifth reference module.

**Architectural facts the public repos must reflect (from the RAS redesign):**

- **Users** owns identity end-to-end — signup, login, password reset, invite acceptance, sessions, users, memberships, role catalogs. The auth adapter (Twilio OTP reference, swap-in pattern) lives inside Users. There is no separate "Registration / Login" repo, module, or service.
- **Customers v2** does NOT auto-attach users at Customer creation. The user who creates a Customer becomes its Owner; bulk attach happens through the Users module, not the Customers module.
- **Workspaces v1.1** is name-only — no `workspace_type` field, no fixed category enum. Workspace meaning is fully expressed by name + module installations (Slack model).
- **Cascade deactivation** is the rule: deactivating a Workspace blocks until all Locations / Orders / Pricing Sets / etc. are deactivated; deactivating a Customer blocks until all Workspaces are deactivated.
- **Three-tier attachment scope** (`company` / `workspace` / `location`) is the data-access shape modules expose for shareable records.
- **`is_operator`** is observability only — it never bypasses Layer 1, Layer 2, or Layer 3 permission checks.
- **Extensible user-type pattern:** the core `users` table carries a single `user_type` field (default `"standard"`); downstream modules add side tables keyed by `user_id` rather than columns to `users`.

---

## Repo mapping

| Public repo (new) | Private source | Role |
|---|---|---|
| `sovereign-portal-shell` | `freshifyv2/portal-shell` | Reference shell — auth, tenant switcher, module loader |
| `sovereign-users-be` | `freshifyv2/users-be` | Reference Users module backend |
| `sovereign-users-fe` | `freshifyv2/users-fe` | Reference Users module frontend |
| `sovereign-companies-be` | `freshifyv2/companies-be` | Reference Companies (UI: "Customers") backend |
| `sovereign-companies-fe` | `freshifyv2/companies-fe` | Reference Companies frontend |
| `sovereign-workspaces-be` | `freshifyv2/workspaces-be` | Reference Workspaces backend |
| `sovereign-workspaces-fe` | `freshifyv2/workspaces-fe` | Reference Workspaces frontend |
| `sovereign-module-template` | NEW (cloned from users-be skeleton) | Empty module starter with `orders-starter` placeholder |
| `sovereign-portal-docs` | NEW (already drafted) | Consolidated documentation repo |

**Decision recap:** Canonical service name is `companies`. UI label is "Customers". This stays consistent across public repos.

---

## Universal strip-and-rename rules

These apply to **every** repo. Run through this list once per repo before opening it for public release.

### Rule 1 — Strip Freshify branding from text

Search and replace across the entire repo:

| Find | Replace |
|---|---|
| `Freshify` (capitalized) | `Sovereign Portal` |
| `freshify` (lowercase, in user-facing strings) | `sovereign-portal` |
| `FRESHIFY_*` env var names | `PORTAL_*` |
| `freshify.io` email/URL references | Generic placeholder (e.g., `example.com`) |
| `@freshify` package scope (npm) | `@sovereign-portal` |

**Caveat:** Some references should stay — `LICENSE` says "© 2026 Freshify, Inc.", `SECURITY.md` says "security@freshify.io". Those are intentional. The replace rule above is for code, configs, env vars, and in-app strings, not for the meta files we already wrote.

### Rule 2 — Strip the violet color tokens

Public release is black / white / grey only. The private app uses Sovereign violet (`--violet`, `--violet-soft`, `--violet-strong` and similar). For each repo:

- Remove the violet custom properties from `:root` declarations
- Replace `var(--violet*)` references with neutral greys or black
- Remove the violet-tinted hover states (e.g., the `.tag-chip.is-link` violet-soft hover from deploy 5.17a)
- Replace logo files (any branded SVG/PNG assets in `/public/`, `/static/`, or `/assets/`)

**Verification:** `grep -r "violet" .` should return zero hits in the public repos.

### Rule 3 — Strip hardcoded URLs

The private repos contain hardcoded Cloud Run URLs from the Freshify GCP project:

```
freshify-portal-shell-sbzaekoo4q-uc.a.run.app
freshify-users-sbzaekoo4q-uc.a.run.app
freshify-workspaces-sbzaekoo4q-uc.a.run.app
freshify-users-fe-sbzaekoo4q-uc.a.run.app
freshify-companies-fe-sbzaekoo4q-uc.a.run.app
freshify-workspaces-fe-sbzaekoo4q-uc.a.run.app
```

All of these must be replaced with environment variables read at startup:

- `PORTAL_SHELL_URL`
- `USERS_BE_URL`, `USERS_FE_URL`
- `COMPANIES_BE_URL`, `COMPANIES_FE_URL`
- `WORKSPACES_BE_URL`, `WORKSPACES_FE_URL`

Provide sensible localhost defaults so `git clone && npm install && npm run dev` works out of the box.

**Verification:** `grep -r "sbzaekoo4q\|a.run.app" .` should return zero hits.

### Rule 4 — Strip GCP project identifiers and secrets

Search for and remove:

- GCP project IDs (`freshifyv2`, etc.) → use `PORTAL_GCP_PROJECT` env var if needed
- Cloud Build trigger names referencing `freshify-*`
- Secret Manager secret names referencing `freshify-*`
- Service account email addresses
- `setup_foundation_secrets.sh` and `setup_foundation_triggers.sh` from the Freshify workspace — these get rewritten generically and live in `sovereign-portal-shell` as reference deployment scripts

**Verification:** `grep -ri "freshifyv2\|projects/freshify" .` should return zero hits.

### Rule 5 — Strip seed data and test users

The private repos contain real user records used for development:

- `Alex Morgan` (operator, used as bootstrap admin)
- Any test workspace named after Freshify clients
- Any seeded company records with real customer data
- Hardcoded email addresses in seed scripts (anything ending in `@freshify.io` or real domains)

Replace with generic seed data:

- Operator: `Operator One` / `operator@example.com`
- Test customers: `Acme Inc.`, `Widgets Co.`, `Globex Corp.`
- Test workspaces: `Workspace Alpha`, `Workspace Beta`

**Verification:** Manual review of every `seed*.{js,ts,json}` file. Open them. Read them. No real names, no real domains.

### Rule 6 — Strip CI/CD config

`.github/workflows/` from the private repos likely references:

- Freshify GCP service accounts (Workload Identity Federation)
- Freshify-specific deploy environments
- Internal Slack webhooks for build notifications

Decision: **delete these workflow files entirely** from the public repos. Replace with a single `ci.yml` that runs `npm test` and `npm run lint` on push. Public users will write their own deploy pipelines.

**Verification:** `find . -path "*.github/workflows/*"` returns at most one file (`ci.yml`) per repo.

### Rule 7 — Strip git history

We do **not** publish the full git history from the private repos. Reasons:

- Old commits contain secrets that were later rotated
- Old commits contain customer references that were later removed
- Old commits contain branding we just stripped above

**Process:**

1. In the private repo, create a clean working tree at the current `main`.
2. Copy the working tree into a fresh `sovereign-*` directory.
3. `cd` into the new directory and `git init`.
4. Make a single initial commit: `git commit -m "Initial public release"`.
5. Add the public remote and push.

We lose blame data and commit history. That's intentional. This is a reference implementation, not a continuation of the private codebase.

### Rule 8 — Strip internal documentation

Each private repo has internal markdown files that don't belong in public:

- `INTERNAL.md`, `RUNBOOK.md`, `ONCALL.md` — delete
- Status docs (`portal_v3_deploy*_status.md`) if any leaked into the repos — delete
- Architecture decision records that reference Freshify clients — review and either generalize or delete
- TODOs and FIXMEs that reference internal Linear tickets or person names — delete or rewrite

Replace the private README with the public README we already drafted (`sovereign-portal-README.md` in the space).

### Rule 9 — Add the meta files

Drop the contents of `sovereign-portal-meta/` into every public repo:

- `LICENSE`
- `NOTICE`
- `SUPPORT.md`
- `CONTRIBUTING.md`
- `SECURITY.md`
- `CODE_OF_CONDUCT.md`
- `.github/ISSUE_TEMPLATE/` (4 files)
- `.github/PULL_REQUEST_TEMPLATE.md`

These are identical across all repos. Same upsell footers, same support routing.

### Rule 10 — Verify the build still works

After all stripping, in a fresh clone:

```bash
git clone git@github.com:sovereign-portal/<repo>.git
cd <repo>
npm install
cp .env.example .env  # provides localhost defaults
npm run dev
```

The repo must boot and reach a working state with no manual fixes required. If it doesn't, you missed an env var or a hardcoded URL.

---

## Per-repo checklists

### `sovereign-portal-shell` (from `freshifyv2/portal-shell`)

Apply all 10 universal rules, plus:

- [ ] Confirm the auth flow uses the Identity Provider abstraction (not hardcoded to Freshify's IdP). Document the IdP swap in the README.
- [ ] Strip the Freshify favicon and replace with a generic one
- [ ] Strip the violet-soft tinted tag-chip hover state from the chip CSS
- [ ] Replace the Freshify logo in the top-left of the shell with a neutral "Sovereign Portal" wordmark (black on white)
- [ ] Verify the legacy redirect logic (added 5.17a, commit `e012536`) is generic and not pointing at Freshify-specific paths
- [ ] Test the tenant switcher with seeded `Operator One` against generic customer seeds
- [ ] Confirm `.env.example` includes all required env vars with localhost defaults: `PORTAL_SHELL_PORT`, `USERS_BE_URL`, `COMPANIES_BE_URL`, `WORKSPACES_BE_URL`, IdP config
- [ ] Add a `docs/deploying.md` that references SUPPORT.md for paid deployment help

### `sovereign-users-be` (from `freshifyv2/users-be`)

**The Users module owns identity end-to-end — both the pre-authenticated and authenticated surfaces. Anything that used to live in a separate RLG (Registration / Login) repo or service must land here, not in a new repo.**

Apply all 10 universal rules, plus:

- [ ] Confirm the repo contains both surfaces: pre-auth (`/v1/auth/signup`, `/v1/auth/login`, `/v1/auth/password-reset`, `/v1/auth/invites/accept`) and post-auth (`/v1/users`, `/v1/users/me`, `/v1/users/:id/memberships`, `/v1/users/:id/roles`). If the private repo splits these across two services, merge them before publishing.
- [ ] Confirm Users owns these collections: `users`, `sessions`, `auth_tokens`, `invites`, `password_resets`, `user_company_memberships`, `user_workspace_memberships`, `user_module_memberships`, `role_catalogs`, `audit_events`. The conformance suite (`sovereign-portal verify`) checks this list.
- [ ] Implement the **self-serve signup** path: create-user-then-create-company is the default; the user becomes the Customer Owner in the same transaction via `framework.scope.createWithOwner`.
- [ ] Implement the **two distinct SMI hooks** at `/smi/users/record-status` (per-record liveness; takes `{recordType, recordId}` and returns `{exists, active, scope?, reason?}`) and `/smi/users/dependency-status` (per-scope cascade gate; takes `{scopeKind, scopeId}` and returns `{module, scopeKind, scopeId, canDeactivate, blockers}`). Users blocks scope deactivation only if active memberships still reference the scope. The two hooks have different shapes and answer different questions — see SMI §3.
- [ ] The `users` schema carries a single `user_type` field (default `"standard"`). Do NOT bake driver / sub-contractor / etc. into the core schema; the extensible side-table pattern handles those downstream.
- [ ] Implement the auth adapter interface (§8 of the SMI spec): `resolve(request) → IdentityContext`, `startSignIn`, `completeSignIn`, `signOut`. Ship the **Twilio OTP reference adapter** as the default. Document the swap path for Auth0 / Okta / Cognito / Clerk.
- [ ] Strip operator bypass code path if it's still in `listMyCompanies` / equivalent endpoints. The 5.17a notes flagged this. The public release ships **without** operator bypass — operators get tenant-switcher visibility plus actual memberships, never a Layer 1/2/3 short-circuit.
- [ ] Seed the bootstrap admin generically (`Operator One`, not `Alex Morgan`). Mark the seed with `is_operator: true` to demo the tenant-switcher "view all" path — but the seed must hold actual Company/Workspace memberships for the data it touches.
- [ ] Strip the Freshify-specific JWT issuer config from `.env` defaults.
- [ ] Verify the SMI `getRoleCatalog` / `upsertRoleRecord` / `deleteRoleRecord` surface matches the public spec exactly. The catalog is per-platform-instance and edits are audit-logged.
- [ ] Add an `examples/` folder with curl recipes for: signup, login, accept-invite, create-Customer-as-Owner, create-Workspace-as-Owner.
- [ ] `.env.example` includes: `MONGODB_URI=mongodb://localhost:27017/sovereign-users`, `JWT_ISSUER`, `JWT_AUDIENCE`, `PORT=4001`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_VERIFY_SID` (with safe placeholders).

### `sovereign-users-fe` (from `freshifyv2/users-fe`)

Apply all 10 universal rules, plus:

- [ ] Ship the full pre-auth surface alongside the authenticated one: `/signup`, `/login`, `/forgot-password`, `/reset-password/:token`, `/invites/:token/accept`. These pages do NOT live in a separate `registration-login-fe` repo. If the private repo currently splits them, fold them in.
- [ ] The post-signup flow lands on a "Create your Customer" screen (Slack-style). The user creating it becomes the Customer Owner in the same transaction. No "please ask an admin to attach you" interstitial — self-serve is the default path.
- [ ] The new-user wizard does NOT include a "Company" step at user creation — attachment to a Customer happens via the Users module's Memberships tab after the user exists, or via invite acceptance. (Customers v2 stripped user-attach from Company creation; the FE must match.)
- [ ] The Users list page exposes a `user_type` filter (default value `"standard"`) without baking any specific user-type values into the dropdown options — read them from the catalog.
- [ ] Strip violet from the user list, user detail, new-user wizard, and pre-auth screens (signup / login / password reset).
- [ ] Strip the Freshify-specific user role labels — keep the generic roles only (`admin`, `member`, plus any roles defined in the public SMI spec).
- [ ] Remove the privacy banner copy that references Freshify.
- [ ] `.env.example` includes: `USERS_BE_URL=http://localhost:4001`, `PORT=3001`.

### `sovereign-companies-be` (from `freshifyv2/companies-be`)

**Customers v2 stripped user-attach from Company creation. The BE must enforce this even if the FE accidentally sends a user list.**

Apply all 10 universal rules, plus:

- [ ] **Critical:** the canonical name stays `companies`. Do not rename to `customers` in code. Only the UI label in the FE says "Customers".
- [ ] **`POST /v1/companies` writes exactly one `user_company_memberships` row** — the Owner row for the creating user (`createWithOwner`). If the request body includes a `users` or `memberships` array, return `400 user_attach_not_supported` with a pointer to the Users module's bulk-attach API.
- [ ] Provide a `company_type` enum on the schema with values `Enterprise | Client | Sub-Contractor | Partner | Affiliate`. "Sub-Contractor" is a filtered view on the Customers list — it is NOT a separate module or repo. The reference seeds include one of each type.
- [ ] Implement the two distinct SMI hooks: `/smi/companies/record-status` (per-record liveness) and `/smi/companies/dependency-status` with `scopeKind: "company"` returning blockers when active Workspaces still exist under the company. Customer deactivation MUST be refused while any Workspace under it is still active.
- [ ] Strip the operator bypass from `listCompanies` (per 5.17a notes). Replace with module-admin gating decided in 5.17a. Operators see the `/v1/admin/companies` cross-tenant directory only in the "Operator view" virtual scope; per-tenant requests obey Layer 1/2/3 normally.
- [ ] Seed generic companies (`Acme`, `Widgets`, `Globex`) — no real Freshify customers. Tag each seed with a different `company_type` value.
- [ ] Verify the audit log enrichment writes `operatorReason` per the public SMI spec (`support` / `incident` / `audit` / `migration` / `impersonation`).
- [ ] `.env.example` includes: `MONGODB_URI=mongodb://localhost:27017/sovereign-companies`, `PORT=4002`.

### `sovereign-companies-fe` (from `freshifyv2/companies-fe`)

Apply all 10 universal rules, plus:

- [ ] All UI strings say "Customers" — verify no leftover "Companies" labels (the original Freshify pivot).
- [ ] The "New Customer" wizard does NOT include a user-attach step. The flow is: pick a name, pick a `company_type`, submit — creator becomes Owner in the same transaction. "Invite teammates" lives on the Customer detail page after creation.
- [ ] Surface `company_type` as a filterable chip on the Customers list (`Enterprise` / `Client` / `Sub-Contractor` / `Partner` / `Affiliate`). "Sub-Contractor" is a filtered view, NOT a separate page.
- [ ] The Customer deactivation button is disabled when `dependency-status` returns `canDeactivate: false` (active Workspace blockers present), with an inline message naming the blocking Workspaces.
- [ ] Strip violet from the customer list, customer detail, and registry screens.
- [ ] Strip the per-record settings cog branding.
- [ ] `.env.example` includes: `COMPANIES_BE_URL=http://localhost:4002`, `PORT=3002`.

### `sovereign-workspaces-be` (from `freshifyv2/workspaces-be`)

**Workspaces v1.1 is name-only. Strip `workspace_type` and anything that branches on it.**

Apply all 10 universal rules, plus:

- [ ] **Schema strip:** remove `workspace_type` from the `workspaces` collection schema. Run the migration to drop the column from existing seeds before publishing. The reference workspace is `{ name, companyId, ownerUserId, createdAt, updatedAt }` — nothing else.
- [ ] **Code strip:** remove every branch that switches on `workspace_type`. The framework infers Workspace meaning from name + installed modules + memberships, not from a typed classifier.
- [ ] **`POST /v1/workspaces`** uses `framework.scope.createWithOwner` — creator becomes Workspace Owner in the same transaction. The Owner is transferable by a Super Admin via `transferOwner`, audit-logged.
- [ ] **Join requests require Admin approval** (no auto-admit). The endpoint is `POST /v1/workspaces/:id/join-requests` and the approve endpoint is gated by the Workspace Admin role.
- [ ] Implement the two distinct SMI hooks: `/smi/workspaces/record-status` (per-record liveness) and `/smi/workspaces/dependency-status` with `scopeKind: "workspace"` returning blocking dependents (active Locations, Orders, Pricing Sets). Workspace deactivation MUST be refused while any dependent is active.
- [ ] **Three-tier attachment scope on Pricing Sets and Locations** (`company` / `workspace` / `location`). The BE recognizes `attachmentScope` on inbound writes and stores it. Reads respect the scope filter from Layer 3.
- [ ] Strip operator bypass from `listWorkspaces` (per the 5.17a sequencing note: seed admins → flip bypass off → smoke).
- [ ] Verify the workspace roles match the public SMI spec defaults (Owner / Manager / Member / Viewer — no Admin tier; §10.4.2).
- [ ] Seed generic workspaces (`Workspace Alpha`, `Workspace Beta`) with no `workspace_type` field.
- [ ] `.env.example` includes: `MONGODB_URI=mongodb://localhost:27017/sovereign-workspaces`, `PORT=4003`.

### `sovereign-workspaces-fe` (from `freshifyv2/workspaces-fe`)

Apply all 10 universal rules, plus:

- [ ] The "New Workspace" wizard has exactly one field: `name`. No `workspace_type` selector, no category dropdown. Creator becomes Workspace Owner on submit.
- [ ] The Workspace detail page surfaces installed modules, member count, and the deactivation control. The deactivation button is disabled when `dependency-status` returns blockers, with an inline list of blocking records and a link to each blocker's module.
- [ ] The Workspace settings page exposes the three-tier attachment-scope selector (Company-wide / Workspace / Location-specific) on any record-creation form rendered inside the Workspace shell.
- [ ] Owner transfer UI calls `transferOwner` and shows the audit-log entry inline post-transfer.
- [ ] Strip violet from workspace list, workspace detail, registry, roles, and aggregate dashboard screens.
- [ ] Verify the workspace roles UI uses the framework's `getRoleCatalog` (not a custom call).
- [ ] `.env.example` includes: `WORKSPACES_BE_URL=http://localhost:4003`, `PORT=3003`.

---

## New repo: `sovereign-module-template`

This repo does not exist yet. It is the starter every Sovereign Portal user clones when building a new module. It is **not** a reference module — the four reference module types (Shell, Users, Customers, Workspaces) cover that.



**Source.** Start from `sovereign-users-be` (the cleanest BE) and strip it down to a minimal shell.

**Contents:**

```
sovereign-module-template/
├── LICENSE / NOTICE / etc.        # Meta files
├── README.md                      # "How to use this template"
├── package.json                   # Minimal deps: express, mongodb, jsonwebtoken
├── .env.example
├── src/
│   ├── index.js                   # Express boot
│   ├── routes/
│   │   ├── items.js               # CRUD scaffold with TODO markers
│   │   └── roles.js               # SMI getRoleCatalog stub
│   ├── middleware/
│   │   ├── identity.js            # 4-layer permission check stub
│   │   └── audit.js               # Audit log write stub
│   ├── models/
│   │   └── item.js                # MongoDB schema stub
│   └── registry.js                # Module registry self-registration
├── tests/
│   └── smoke.test.js              # "Module boots and registers" smoke test
└── docs/
    ├── 11-section-template.md     # The 11-section module doc template
    └── customization.md           # What to change after cloning
```

**Naming convention.** Throughout the template, the placeholder module is called `orders-starter` so users can search-and-replace `orders` → their actual module name (`invoices`, `shipments`, `tickets`, whatever).

**Verification.** Clone the template, search-replace `orders-starter` to `invoices`, and confirm:

- The module boots on `npm run dev`
- The module self-registers with the portal-shell
- The smoke test passes
- A CRUD call to `POST /v1/invoices` works with a valid JWT

---

## Two-weekend execution sequence

### Weekend 1 — Foundation

**Saturday (4 hours)**

1. Create `github.com/sovereign-portal` org
2. Create empty repos (all 9) with default branch `main` and Apache 2.0 selected
3. Strip and push `sovereign-portal-shell` (highest risk — auth and tenant switcher)
4. Strip and push `sovereign-users-be` and `sovereign-users-fe`
5. **Smoke gate:** clone all three on a clean laptop, run `npm install && npm run dev`, log in with seed `Operator One`, see the empty Users module load

**Sunday (4 hours)**

6. Strip and push `sovereign-companies-be` and `sovereign-companies-fe`
7. Strip and push `sovereign-workspaces-be` and `sovereign-workspaces-fe`
8. **Smoke gate:** full local stack boots, all four modules visible, switch tenants, seed data loads
9. Final grep audit across all 7 repos: `freshify`, `violet`, `sbzaekoo4q`, real customer names — must return zero
10. Make repos visible to one trusted external reviewer (not Krish, not Ryan yet — someone outside Freshify) and get a 30-min "does this look public-ready" gut check

### Weekend 2 — Template and docs

**Saturday (4 hours)**

11. Build `sovereign-module-template` from the users-be skeleton
12. Write the 11-section module doc template (referenced by README and permission-model doc but doesn't exist yet)
13. **Smoke gate:** clone the template, rename to `invoices`, register with the running portal-shell, CRUD works

**Sunday (4 hours)**

14. Stand up `sovereign-portal-docs` as a single repo holding the six public docs (README, quickstart, SMI spec, permission-model, registry+settings, anti-patterns) plus the 11-section template
15. Cross-link: every repo README links to `sovereign-portal-docs`
16. Make all 9 repos public
17. **Public gate:** in an incognito browser, walk through the 30-minute quickstart from the public README end-to-end. If anything is missing or unclear, the public-release week 1 backlog opens here.

### Verification gates summary

| Gate | What we check | If it fails |
|---|---|---|
| Saturday W1 smoke | Shell + users boots clean | Stop. Fix before continuing. |
| Sunday W1 smoke | Full 4-module stack boots clean | Stop. Fix before continuing. |
| Sunday W1 audit | Grep returns zero on forbidden tokens | Stop. Re-strip. |
| Sunday W1 review | External reviewer thumbs-up | Address feedback before weekend 2. |
| Saturday W2 template | Clone-rename-register works | Stop. Template is the upsell hook for "build your own module" — must be perfect. |
| Sunday W2 quickstart | 30-min quickstart works in incognito | Stop. Fix docs before going public. |

---

## What NOT to do

- **Don't** publish the private repos directly with sensitive commits squashed — start fresh, single initial commit.
- **Don't** keep the violet color tokens as "themeable defaults" — they're a Sovereign brand asset, not a public reference.
- **Don't** tell Krish or Ryan about the public release until weekend 2 ends and quickstart passes. Locked decision from earlier this session — get the work done, then loop them in.
- **Don't** add CI/CD workflows that reference Freshify infrastructure. Public users write their own.
- **Don't** put real customer names, real tenants, or real email addresses anywhere — search hard, then search again.
- **Don't** publish without all 11 meta files in every repo. The upsell architecture only works if SUPPORT.md is one click away from every issue and PR.

---

## After public release

The work continues:

1. **Monitor** Discussions and Issues in the first 14 days — answer the easy ones, route the hard ones to SUPPORT.md.
2. **Track** which paths trigger the SUPPORT.md hooks — bug-template footer, PR-template footer, SECURITY.md commercial section. Pattern-match on which framings convert.
3. **Refine** the docs based on real questions — every Discussion thread with three or more replies is a doc gap.
4. **Build** the next reference module if Discussions show consistent demand for a specific shape (e.g., Orders, Invoices, Tickets). Each new reference module is a marketing asset for the Sovereign Software Blueprint paid offering.

---

*Internal Freshify document. Not for publication.*
