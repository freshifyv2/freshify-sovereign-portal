# Sovereign Portal

**A working sovereign foundation for owned business software — Users, Customers, Workspaces, and a Standard Module Interface for everything you build on top.**

Sovereign Portal is the open-source foundation underneath modern modular business software. You get three working sovereign modules (Users, Customers, Workspaces), a portal shell that hosts them, a Standard Module Interface (SMI) every module conforms to, a reference business module with an AI agent sidecar, and a module template you copy to build the next one. Self-host on your own cloud. No SaaS tenant. No license keys. No tiered access.

It runs locally in one command.

```bash
git clone --recursive https://github.com/freshifyv2/freshify-sovereign-portal.git
cd freshify-sovereign-portal
cp .env.example .env
docker compose up
```

Then open <http://localhost:3000>. The bootstrap operator's login OTP prints to the `users-be` container logs on first boot.

---

## What you see when it's running

> Screenshots below are rendered from the canonical Sovereign Portal design system. The local `docker compose` stack ships the same UI.

### Customers list — typed, gear-per-record, dependency-aware

The Customers module (canonical key `companies`, default UI label "Customers") ships with five customer types out of the box (Enterprise, Client, Sub-Contractor, Partner, Affiliate). Every record gets a gear icon — the standard entry point into per-record settings.

![Customers list with gear icon](./docs/screenshots/01-companies-list.png)

### Registry-driven filter chips

Filter chips are driven by the module's registry, not hardcoded UI strings. The list, search, and counts all run server-side as pure server components.

![Customers list with filter pills](./docs/screenshots/02-companies-filter.png)

### Multi-tenant operator switching

Operators with cross-tenant memberships switch tenants from the account pulldown. There is no privileged "see everything" bypass — operators see what their memberships grant them, audit-logged on every cross-tenant read.

![Tenant switcher](./docs/screenshots/03-tenant-switcher.png)

### Module Settings — the registry + governance pattern

Every module ships the same five-section Settings page: Module Admins, Available Roles, Default Role, Capabilities, and a read-only view of the module's Registry. The page below is the Customers module's Settings.

![Customers module settings](./docs/screenshots/04-module-settings.png)

### Per-record settings — same pattern, different scope

The gear icon on any record opens a per-record settings page at `/dashboard/{module}/{id}/settings`. Governance lives in module-level settings; per-record overrides live here.

![Per-record settings](./docs/screenshots/05-per-record-settings.png)

### Same pattern across every module — Workspaces

The Workspaces Module Settings page. Identical structure to the Customers page above — same five sections, same registry view, same governance contract. Every sovereign module looks structurally identical.

![Workspaces module settings](./docs/screenshots/06-workspaces-settings.png)

### Same pattern across every module — Users

The Users Module Settings page. Identical structure again. The Standard Module Interface is what makes this consistency possible — not a UI framework, but a contract every module conforms to.

![Users module settings](./docs/screenshots/07-users-settings.png)

### Account page — identity owned by the Users module

The Users module owns identity end-to-end: account page, password change, notification preferences, deactivation, and the membership/tenant model that powers the switcher.

![Account page](./docs/screenshots/08-account.png)

---

## What's in the box

**Foundation modules** (the working sovereign foundation):

- **Users** — signup, login, password reset, invite acceptance, sessions, role catalogs, memberships. Pluggable auth adapter; Twilio OTP reference implementation ships as default.
- **Customers** — multi-type companies with three-tier attachment scope (`company` / `workspace` / `location`) and dependency-aware deactivation.
- **Workspaces** — name-only workspaces with Owner transfer, join-request approval flow, and per-Workspace module installations.

**Portal shell** — the navigation chrome, the tenant switcher, the cross-module routing layer, the audit feed surface, the legacy-redirect handler.

**Standard Module Interface (SMI)** — the contract every sovereign module conforms to. Module registry, peer registry, per-record liveness, dependency cascade, auth adapter, role catalog, agent sidecars. Full spec in [`docs/smi-spec.md`](./docs/smi-spec.md).

**Reference business module** — Customer Support, demonstrating a sovereign business module + its AI agent sidecar composing against the foundation through the standard peer-registry mechanism. Lives in `modules/support-be`, `modules/support-fe`, `modules/support-agent`. Built directly from `module-template/` — same code path, no special treatment.

**Module template** — `module-template/` is what you copy to build a new module. BE + FE + optional agent sidecar. The 30-minute quickstart in [`docs/quickstart.md`](./docs/quickstart.md) takes you from `cp -r module-template orders-fe` to a running sovereign Orders module that lists, creates, and shows orders scoped to a Workspace, with Module Settings, Module Registry, agent hooks, and full SMI conformance.

---

## What's not in the box

- **No hosted SaaS tenant.** You self-host on your own cloud. Always.
- **No license keys, no tiered access.** Everything in the public repo is everything you get.
- **No no-code visual builder.** Your team writes JavaScript modules against the Standard Module Interface. If they can't, this is not the product for you — talk to [Freshify](https://freshify.io) about a custom engagement instead.
- **No business modules.** Orders, Pricing, Locations, Billing — none of them ship in this repo. They are what you build on top. The `module-template` shows you how.
- **No marketplace.** Each module is a sovereign repo you control.

---

## The repos

Sovereign Portal is a meta-repo that pulls each module as a git submodule. The actual code lives in 10 sovereign repos:

| Repo | What it is | Port (local) |
|---|---|---|
| [`freshify-sovereign-portal`](https://github.com/freshifyv2/freshify-sovereign-portal) (this repo) | Meta-repo, compose file, top-level docs, conformance suite | — |
| [`freshify-sovereign-users-be`](https://github.com/freshifyv2/freshify-sovereign-users-be) | Users module backend | 4001 |
| [`freshify-sovereign-users-fe`](https://github.com/freshifyv2/freshify-sovereign-users-fe) | Users module frontend | 3001 |
| [`freshify-sovereign-companies-be`](https://github.com/freshifyv2/freshify-sovereign-companies-be) | Customers module backend | 4002 |
| [`freshify-sovereign-companies-fe`](https://github.com/freshifyv2/freshify-sovereign-companies-fe) | Customers module frontend | 3002 |
| [`freshify-sovereign-workspaces-be`](https://github.com/freshifyv2/freshify-sovereign-workspaces-be) | Workspaces module backend | 4003 |
| [`freshify-sovereign-workspaces-fe`](https://github.com/freshifyv2/freshify-sovereign-workspaces-fe) | Workspaces module frontend | 3003 |
| [`freshify-sovereign-portal-shell`](https://github.com/freshifyv2/freshify-sovereign-portal-shell) | Portal shell (navigation, tenant switcher, routing) | 3000 |
| [`freshify-sovereign-module-template`](https://github.com/freshifyv2/freshify-sovereign-module-template) | Reference module + agent. Copy to build your own. | — |
| [`freshify-sovereign-portal-cli`](https://github.com/freshifyv2/freshify-sovereign-portal-cli) | Scaffolding + conformance: `sovereign-portal new`, `sovereign-portal verify` | — |

The portal shell, the meta-repo, and the CLI are framework infrastructure. The other seven repos are sovereign modules — same contract as anything you'll build.

---

## Documentation

| Doc | What it covers |
|---|---|
| [`docs/quickstart.md`](./docs/quickstart.md) | 30-minute walkthrough from `cp -r module-template orders-fe` to a running Orders module. Start here. |
| [`docs/smi-spec.md`](./docs/smi-spec.md) | The Standard Module Interface — registry, peer registry, record-status, dependency-status, auth adapter, agent sidecars. The contract every module conforms to. |
| [`docs/permission-model.md`](./docs/permission-model.md) | The four-tier scope (User → Customer → Workspace → Module) and three-layer permission check. The conceptual model. |
| [`docs/module-registry-and-settings.md`](./docs/module-registry-and-settings.md) | The Module Registry shape every module exports, and the Module Settings page every module surfaces. |
| [`docs/anti-patterns.md`](./docs/anti-patterns.md) | 20 mistakes the framework is built to prevent, with the right fix for each. Grep this when something feels wrong. |
| [`docs/code-stripping-checklist.md`](./docs/code-stripping-checklist.md) | Internal checklist used to prepare the foundation repos for public release. Useful if you want to understand the boundary between framework and deployment-specific code. |

---

## Quickstart for builders

The 30-minute walkthrough lives in [`docs/quickstart.md`](./docs/quickstart.md). Summary:

1. **Boot the foundation.** `docker compose up`. Verify the dashboard renders at <http://localhost:3000>.
2. **Copy the template.** `cp -r module-template modules/orders-be && cp -r module-template modules/orders-fe`. Rename in the registry.
3. **Fill in the registry.** Edit `orders-be/src/moduleRegistry.js` with the canonical fields (key, label, attachmentScopes, dependencies, smiPath, ownedCollections, events, capabilities, settingsSchema, perRecordSettingsSchema, roles).
4. **Add your domain routes.** The template ships the SMI plumbing (`/smi/*`, `/agent/*`); you add `/v1/orders` (or whatever your module's surface is) and a Mongoose model.
5. **Wire the FE.** The template's `ModuleSettings.jsx` already maps the registry to the five Settings sections — you write the list page, the detail page, the new-record form.
6. **Verify.** `npx sovereign-portal verify modules/orders-be` runs the conformance suite. Green means you're shipping a sovereign module.

You will write zero auth code, zero tenant-scoping logic, zero settings-page boilerplate, and zero registry-discovery code. All of that comes from the framework.

---

## Production deployment

The compose file is for local development. For production, each module is a standard Node.js / Vite service that runs anywhere — Kubernetes, Cloud Run, Fargate, an EC2 box. The contracts in the SMI spec are network-protocol-level (HTTP + JSON), so a real deployment looks like:

- Each BE deployed independently with its own MongoDB connection
- Each FE built once and served from your CDN or behind your shell
- Portal shell deployed once, configured with the peer module URLs
- A secret manager holding `SERVICE_PRINCIPAL_SECRET`, `USER_JWT_SECRET`, and the IdP credentials
- A managed MongoDB cluster (Atlas, DocumentDB, self-hosted)

We do not ship Terraform, Helm charts, or Kubernetes manifests in the public repo because they would presuppose a specific cloud and would lock you into Freshify's opinions about your deployment. If you want Freshify to deploy and operate Sovereign Portal for you, see [SUPPORT.md](./SUPPORT.md) — production deployment is a paid engagement.

---

## Contributing

We accept issues, PRs, and module contributions. See [CONTRIBUTING.md](./CONTRIBUTING.md) for the contribution process, [CODE_OF_CONDUCT.md](./CODE_OF_CONDUCT.md) for community standards, and [SECURITY.md](./SECURITY.md) for vulnerability disclosure.

The single highest-leverage contribution is a new sovereign module published against the SMI. If you ship one, open an issue tagged `module-showcase` — we will link it from the README.

---

## License

Apache 2.0. See [LICENSE](./LICENSE) and [NOTICE](./NOTICE).

This is genuine open source — no Business Source License, no Functional Source License, no "open core with paid features," no license keys gating functionality. Everything in this repo is everything you get.

---

## Support

Community support is via GitHub Issues. For paid production support — deployment, operations, custom module builds, architecture consulting — see [SUPPORT.md](./SUPPORT.md).

Sovereign Portal is maintained by [Freshify, Inc.](https://freshify.io), a design and architecture consultancy specializing in modular service architecture for mid-market companies.
