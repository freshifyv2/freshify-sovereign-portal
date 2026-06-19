# Changelog

All notable changes to Sovereign Portal are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Sovereign Portal is a multi-repo project. This changelog tracks releases across all eight component repos under the [`freshifyv2`](https://github.com/freshifyv2) org. Every component is tagged together at the same version.

## [Unreleased]

## [0.1.0] — 2026-06-19

First public release.

### Added

- **Portal shell** ([`freshify-portal-shell`](https://github.com/freshifyv2/freshify-portal-shell)) — host application with operator dashboard, tenant switcher, audit feed, invites, portal settings, cross-module routing layer.
- **Shared design-system package** ([`freshify-portal-shell-ui`](https://github.com/freshifyv2/freshify-portal-shell-ui)) — neutral black/white/grey theme, layout primitives, list-card / metric-card / data-table / btn family, page-header + breadcrumb, filter pills.
- **Users module** ([`freshify-users`](https://github.com/freshifyv2/freshify-users) + [`freshify-users-fe`](https://github.com/freshifyv2/freshify-users-fe)) — pluggable auth (Twilio Verify reference adapter), email+password login, phone+OTP login, sessions, profile, invite issue/resend/accept, module-admin grants, audit events.
- **Customers module** ([`freshify-companies`](https://github.com/freshifyv2/freshify-companies) + [`freshify-companies-fe`](https://github.com/freshifyv2/freshify-companies-fe)) — companies with scoped roles, registry, per-record + module settings, dependency cascade against Workspaces.
- **Workspaces module** ([`freshify-workspaces`](https://github.com/freshifyv2/freshify-workspaces) + [`freshify-workspaces-fe`](https://github.com/freshifyv2/freshify-workspaces-fe)) — workspaces with cross-company membership, scoped roles, per-record + module settings, dependency dashboards.
- **Standard Module Interface (SMI)** — every module conforms: `/smi/registry`, `/smi/records`, `/smi/health`, `/smi/dependencies`, `/agent/*` (optional), event publication contract, peer-registry discovery. Full spec in [`docs/smi-spec.md`](./docs/smi-spec.md).
- **One-command local stack** — `git clone` → `./scripts/clone-all.sh` → `cp .env.example .env` → `docker compose up --build` boots eight services (Mongo + 3 BEs + 3 FEs + portal shell) in ~90 seconds on a warm cache.
- **Bootstrap operator** — first boot seeds an `operator@sovereign.local` / `sovereign-portal-admin` account with portal-scope Module Admin on all three foundation modules. Overridable via `SEED_OPERATOR_*` env vars.
- **Sample seed data** — 5 sample customers (Atlantic Logistics, Cascade Health, Midwest Manufacturing, Northwind Logistics, Sovereign Corp), 5 sample workspaces, 5 sample users distributed across them.
- **Documentation** — README with full positioning, repo table, "not in the box" stance; `docs/smi-spec.md`, `docs/permission-model.md`, `docs/module-registry-and-settings.md`, `docs/anti-patterns.md`, `docs/quickstart.md`, `docs/code-stripping-checklist.md`.
- **Governance files** — LICENSE (Apache-2.0), NOTICE, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, SUPPORT in every public repo.

### Not in the public foundation

The following are part of [Freshify](https://freshify.io)'s commercial offering rather than the public release. The SMI spec is complete and stable — you can build everything below yourself against the public foundation. The paid offering exists to compress that timeline:

- **Production module library** — BE+FE pairs for common business domains (Orders, Inventory, Billing, Locations, Support, CRM).
- **Agent training packs** — system prompts, evaluation harnesses, golden datasets, RAG indexing recipes for sovereign-module AI agents.
- **Production deployment + managed operations** — Terraform/Pulumi recipes, Cloud Run / EKS / Fargate runbooks, secrets layout, migration plans from legacy SaaS, on-call coverage.

[Unreleased]: https://github.com/freshifyv2/freshify-sovereign-portal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/freshifyv2/freshify-sovereign-portal/releases/tag/v0.1.0
