# Module Registry & Settings

**The pattern every sovereign module uses to describe itself and govern itself.**

---

This document specifies two structural pieces every Sovereign Portal module ships with:

1. A **Module Registry** — a small block of canonical metadata every sovereign module publishes about itself.
2. A **Module Settings page** at `/dashboard/{module}/settings` — the home for module-wide governance (Module Admins, Available Roles, Default Role, and a read-only view of the Registry).

Both pieces shipped first in the Users / Customers / Workspaces foundational modules; the `module-template` starter includes them; every module in the conformance suite implements them. Together they are the structural answer to "how does a module identify itself, expose its governance surface, and stay loose-coupled to its peers?"

This document is the contract. The SMI spec (`docs/smi-spec.md`) is the broader interface; this is the specific pattern for the registry and the settings page that the SMI assumes you have.

---

## 1. Why this matters

For modules to compose against each other without tight coupling, three things have to be true:

1. A module must be able to identify itself by a stable ID, independently of the deployment.
2. A module must be able to describe its surface area (routes, collections, auth ownership, settings ownership) without exposing implementation details.
3. Module-wide concerns (who governs the module, what roles it recognizes, what role a new invitee gets) must live in a module-owned location, not scattered across business logic.

The **Registry** solves (1) and (2). The **Settings page** solves (3) and surfaces the Registry to operators.

Concretely, the registry + settings pattern lets you:

- Have the Orders module reference the Customers module by canonical module ID (`companies` → `companies-be`) without hardcoding a service URL.
- Have the Workspaces module query the Users module for the Default Role to assign on invite, without Workspaces needing to know Users' role vocabulary.
- Give a support operator scoped access by adding them as a Module Admin on a single module, instead of granting them a blanket cross-tenant bypass.

Without this pattern, you end up with hardcoded references between FEs and BEs (the exact tight coupling sovereign modules exist to escape), and module-wide governance ends up living in business-logic code on the wrong side of the sovereign boundary.

---

## 2. The Module Registry

Each module publishes a small block of canonical metadata about itself. The Registry lives in two places:

- **In the module's source-of-truth document**, as part of Section 1 (Module Identity). This is the design-review source of truth.
- **Surfaced read-only on the Settings page**, in Section 4. This is what operators see at runtime.

### 2.1 Registry shape

The registry is a plain JavaScript object exported by the module's BE at `src/moduleRegistry.js`. There is no typed package, no `@sovereign-portal/core` import, no `ModuleDescriptor` interface — the shape **is** the contract.

| Field | Type | Description |
|---|---|---|
| `key` | string | Canonical, stable identifier. Snake-case or kebab-case. Never changes after release. Other modules reference this. |
| `label` | string | Human-readable label for operator UI. May be relabeled per deployment (see §5). |
| `registryVersion` | string | The registry/SMI contract version this module implements. `v0.2`, `v1`, etc. |
| `attachmentScopes` | string[] | Subset of `["company", "workspace", "location"]` this module's records can be attached to. Almost every business module supports `workspace`; some also support `company` and/or `location`. |
| `dependencies` | string[] | Canonical `key` values of peer modules this module hard-depends on (e.g. `["users", "workspaces"]`). Used by the framework for boot-order and dependency-status checks. |
| `smiPath` | string | URL prefix on this module's BE where SMI hooks are mounted. Convention: `/smi/{key}`. |
| `ownedCollections` | string[] | Mongo collections (or equivalent schemas) this module owns. Sovereignty rule applies — no other module reads them. |
| `events` | object | `{ publishes: string[], subscribes: string[] }` — canonical event names. Publishes is the surface other modules may listen on; subscribes is what this module reacts to. |
| `capabilities` | object[] | Module-level capability toggles. Each entry: `{ key, label, togglable, default }`. Capabilities gate optional features (e.g. `agent_inline_classify`, `bulk_import`) and are surfaced on the Settings page. |
| `settingsSchema` | object | JSON-schema-ish descriptor of module-wide settings the module persists. Drives the Settings page's editable fields. |
| `perRecordSettingsSchema` | object | JSON-schema-ish descriptor of per-record settings (the gear-icon page at `/dashboard/{key}/{id}/settings`). |
| `roles` | object | `{ defaults: RoleRecord[] }` — the module's default role catalog. From SMI §10. The Settings page surfaces this as Available Roles + Default Role. |

Derived conventions (not stored on the registry — computed by the framework):

- Backend service name: `{key}-be`. Frontend: `{key}-fe`.
- Public route prefix: `/dashboard/{key}` unless the deployment relabels (see §5).
- Module-level settings URL: `/dashboard/{key}/settings`.
- Per-record settings URL: `/dashboard/{key}/{id}/settings`.

Auth ownership is not a registry field. The Users module owns auth by being the Users module; everyone else delegates to it through the standard auth middleware. There is no `owns-auth` / `delegated-to-users` toggle to set.

### 2.2 Worked example — the Users module Registry

```js
// users-be/src/moduleRegistry.js
module.exports = {
  key: "users",
  label: "Users",
  registryVersion: "v0.2",
  attachmentScopes: [],                // Users records do not attach to scopes;
                                       // membership is the attachment
  dependencies: [],
  smiPath: "/smi/users",
  ownedCollections: [
    "users",
    "sessions",
    "invites",
    "audit_events",
    "user_company_memberships",
    "user_workspace_memberships",
    "user_module_memberships",
    "role_catalogs",
  ],
  events: {
    publishes: [
      "users.created",
      "users.deactivated",
      "users.invite.accepted",
      "users.role_granted",
    ],
    subscribes: [],
  },
  capabilities: [
    { key: "sso_login",       label: "SSO Login",         togglable: true,  default: false },
    { key: "twilio_otp",      label: "Twilio OTP",        togglable: true,  default: true  },
  ],
  settingsSchema: {
    sessionTtlHours: { type: "number", default: 24, min: 1, max: 720 },
  },
  perRecordSettingsSchema: {
    // Users has no per-record settings page in v0.2
  },
  roles: {
    defaults: [
      { key: "users.admin",  label: "Admin",  isDefault: false },
      { key: "users.member", label: "Member", isDefault: true  },
      { key: "users.viewer", label: "Viewer", isDefault: false },
    ],
  },
};
```

### 2.3 Worked example — a business module Registry

```js
// support-be/src/moduleRegistry.js  (Customer Support module — also the template's demo)
module.exports = {
  key: "support",
  label: "Customer Support",
  registryVersion: "v0.2",
  attachmentScopes: ["workspace"],
  dependencies: ["users", "workspaces"],
  smiPath: "/smi/support",
  ownedCollections: ["tickets"],
  events: {
    publishes: [
      "support.ticket.created",
      "support.ticket.classified",
      "support.ticket.replied",
      "support.ticket.resolved",
    ],
    subscribes: [
      "users.deactivated",       // reassign open tickets
      "workspaces.deactivated",  // cascade close
    ],
  },
  capabilities: [
    { key: "agent_inline_classify", label: "Auto-classify on arrival",      togglable: true, default: false },
    { key: "agent_drafts",          label: "AI draft replies for operators", togglable: true, default: true  },
    { key: "agent_auto_act",        label: "Agent may send replies directly", togglable: true, default: false },
  ],
  settingsSchema: {
    autoCloseAfterDays: { type: "number", default: 14, min: 1, max: 365 },
    defaultPriority:    { type: "enum",   options: ["low", "normal", "high"], default: "normal" },
  },
  perRecordSettingsSchema: {
    assignee:     { type: "string", description: "User key of current owner" },
    silenceAgent: { type: "boolean", default: false },
  },
  roles: {
    defaults: [
      { key: "support.admin",  label: "Admin",  isDefault: false },
      { key: "support.member", label: "Member", isDefault: true  },
      { key: "support.viewer", label: "Viewer", isDefault: false },
    ],
  },
};
```

Every module — Users, Customers, Workspaces, Orders, Pricing, Locations, Billing, Customer Support, and every module yet to be designed — exports the same registry shape from `src/moduleRegistry.js`. Field values differ; the shape does not.

### 2.4 Registry consumption

Other modules read a peer's registry through the peer registry client (see SMI §5). The peer registry is a tiny JS module — each BE ships one — that wraps `fetch` calls against the canonical SMI endpoints of its peers.

```js
// orders-be/src/peerRegistry.js
const usersRegistry = await peers.get("users");
if (usersRegistry?.registryVersion?.startsWith("v0.")) {
  // safe to call functions assuming v0.x contract
}
```

Operator tooling reads each registry to render service maps, dependency graphs, and the read-only Registry section on Settings pages. Nothing else in the codebase should hardcode a service URL, a collection name, or a route prefix. If you find yourself typing `companies-be` as a string literal in business logic, you are violating the contract — go through the peer registry.

### 2.5 Why fields, not a typed package

Earlier drafts of this framework referenced a `ModuleDescriptor` TypeScript interface shipped in an `@sovereign-portal/core` package. That package does not exist. The registry is intentionally a plain JS object literal:

- It survives every JS/TS build target without import-resolution issues.
- A module that fails to declare a required field fails the conformance check, not a type-check at build time — which means CI catches it on every push, not only inside an IDE.
- It lets the BE, FE, and any sidecar (see §2.6) read the same file with no shared runtime.

The conformance suite (`sovereign-portal verify`) checks the shape. Type-only consumers can derive a TypeScript type from the live shape if they want one in their own codebase — the framework does not ship it.

### 2.6 Agent sidecars and the registry

If a module has an AI agent (see SMI §16), the agent **does not** publish its own registry entry. It is bonded to the parent module and consumes the parent's registry through the same peer-registry mechanism every other consumer uses. The parent module advertises the agent's existence by declaring agent-related capabilities (e.g. `agent_inline_classify`, `agent_drafts`, `agent_auto_act`) in its own `capabilities` array. Operators toggle the agent's behavior from the parent module's Settings page — there is no separate "agents" tab anywhere in the portal.

---

## 3. The Module Settings Page

Each module gets a Settings page at `/dashboard/{module}/settings`. This is **module-wide governance** — distinct from per-record settings, which live at `/dashboard/{module}/{id}/settings`.

The page is organized into five sections, identical across every module: Module Admins, Available Roles, Default Role, Capabilities, and Module Registry.

### 3.1 Page sections

| Section | What it contains |
|---|---|
| **Module Admins** | List of users with module-wide governance rights for this module. The bootstrap rule (§3.3) populates this on install. |
| **Available Roles** | The module's role catalog — sourced from the registry's `roles.defaults` plus any deployment-specific edits. From SMI §10. |
| **Default Role** | The role assigned to new invitees who arrive without an explicit grant. Exactly one role per catalog is marked Default. |
| **Capabilities** | The registry's `capabilities` array, surfaced for operators. Togglable capabilities are editable here; non-togglable ones are read-only. |
| **Module Registry** | Read-only view of the module's Registry block (§2). The "this is who I am" reference for operators. |

### 3.2 Section: Module Admins

Module Admins hold module-wide governance rights — they can edit the role catalog, manage the Default Role, add or remove other Module Admins, and access every record the module owns regardless of Workspace-level scope.

Module Admin is **distinct from** Owner. Owner is a per-instance role (one Owner per `(workspaceId, moduleName)` pair, per SMI §10.4.3). Module Admin is a deployment-wide role — a user can be a Module Admin on the Orders module across every Workspace the deployment hosts.

In practice, Module Admin is the role you assign to:

- The internal team responsible for operating the module
- Support operators when they need cross-tenant visibility into a specific module
- Migration tooling that needs unrestricted access for a bounded window

### 3.3 Module Admin bootstrap rule

The framework needs **some** user to hold module-wide governance the moment a module is installed in a fresh deployment, or there is no path to grant anyone else governance. The bootstrap rule:

> **The first user of a tenant is automatically seeded as a Module Admin on every module installed in that tenant.**

This is enforced by the Users module's invite flow (and account-creation flow for the very first user of a deployment). Subsequent users do not get auto-promoted; they receive the Default Role until a Module Admin assigns them something else.

Module Admins can transfer their seat to another user. The deployment-wide enforcement: **at least one Module Admin must exist per module at all times.** The framework refuses to remove the last Module Admin without a transfer.

### 3.4 Section: Available Roles

The role catalog — the records from SMI §10.4.3 (the module-tier catalog), rendered editable for users with the `manage_roles` capability. See SMI §12 for the full Role Settings UI contract.

A module's role vocabulary is conventionally `{key}.admin`, `{key}.member`, `{key}.viewer`, but the framework does not enforce this — you may define your own. The conformance suite checks the catalog shape, not the names you give the roles.

### 3.5 Section: Default Role

Every catalog has exactly one role marked Default. Invitees who arrive without an explicit role grant get the Default Role. Module Admins can change which role is Default; the framework enforces "exactly one" on save.

In the default module catalog (SMI §10.4.3), the Default Role is `member`. Most deployments do not need to change this.

### 3.6 Section: Module Registry

A read-only block showing the Registry from §2 with every field rendered, plus the `lastReloaded` timestamp from the framework's peer registry. This is the operator's "what am I looking at" view — they can confirm the module's identity, its derived service names, its owned collections, its supported attachment scopes, its dependencies, its published/subscribed events, and its registry version without leaving the page.

### 3.6.1 Section: Capabilities

For any module whose registry declares `capabilities`, the Settings page renders a Capabilities block listing each entry with its label, its current value, and (for togglable capabilities) a toggle. The Capabilities block is where operators turn on/off optional features the module declares — for example, the Customer Support module's `agent_inline_classify` toggle lives here, not on a separate "agents" page.

Non-togglable capabilities are surfaced read-only as proof of what the module supports.

### 3.7 Per-record attachment scope

For modules whose `attachmentScopes` includes more than one tier, individual record-creation forms expose an attachment-scope selector with three options:

- **Company-wide** — every Workspace in this Customer sees the record. Requires `manage_settings` on the Customer.
- **Workspace** — only this Workspace sees the record. The default for most module records.
- **Location-specific** — only the chosen Location sees the record. Available when the deployment runs the Locations module.

The selector defaults to **Workspace**. Switching to **Company-wide** or **Location-specific** is a deliberate act that the framework audit-logs with the role that authorized it. Modules MUST NOT silently widen scope after creation; widening requires a new write at the new scope and an audit event.

---

## 4. Phase A / Phase B

Sovereign Portal ships the Settings page in two phases. Phase A is FE-only (hardcoded data, no BE changes). Phase B is the backend pass that makes the Settings page a live editor of persisted module state.

| Concern | Phase A — UI preview (default) | Phase B — backend (per deployment) |
|---|---|---|
| Module Admins | Hardcoded list in the FE; bootstrap seeded from "first user of tenant" rule | `moduleAdmins` collection with GET/PUT endpoints; editable by existing Module Admins |
| Available Roles | Hardcoded array in the FE | Served by each module's BE from a module registry endpoint |
| Default Role | Marked in the hardcoded FE array | Persisted per-module, editable by Module Admins |
| Registry metadata | Hardcoded in the FE; read-only | Served from the BE; reflects deployment reality (collection names, service URLs, version) |
| Operator visibility | Existing bypass in list endpoints stays in place during Phase A | Drop the operator bypass in `listMyCompanies` / `listWorkspaces` after Module Admins are seeded |

Sovereign Portal ships Phase A as the foundation. Phase B is sequenced per deployment because flipping the operator bypass before Module Admins are seeded breaks support workflows. The Phase B sequencing is captured in §6 below.

### 4.1 Why ship Phase A first

Phase A is fully usable. A team can install Sovereign Portal, deploy modules, see the Settings page render correctly across every module, and confirm the governance surface looks right — without having committed to a backend schema for module-wide governance.

This sequencing reflects a recurring pattern in the framework: **structural decisions ship before persistence decisions.** Once the UI contract is locked, the persistence layer can be added without ripple, and Phase A → Phase B is a clean refactor rather than a redesign.

---

## 5. Naming reconciliation

The framework canonical name for the company-layer module is `companies`. The default UI label is "Customers." This is a **deliberate split** (see also `docs/permission-model.md` §Tier 2):

- **Canonical names** (`key`, derived `{key}-be` / `{key}-fe` service names, collection names, API route paths) stay portable across deployments and never re-label.
- **UI labels** (page titles, navigation labels, breadcrumbs, the deployment's public route prefix override) reflect your deployment's vocabulary.

Practical implications for the Registry:

- `key` is canonical: `companies` (not `customers`). Derived service names are `companies-be` and `companies-fe`.
- `label` is the deployment-facing label: `"Customers"` if the deployment uses that vocabulary, otherwise `"Companies"`.
- The deployment-level route override (set in the portal shell, not on the registry) maps `/dashboard/customers` → the `companies` module. The shell handles the redirect from `/dashboard/companies` → `/dashboard/customers` when a relabel is in effect.
- The UI page title, navigation entry, and breadcrumb say "Customers" (or whatever the deployment labels it).

If your deployment introduces a new label for any other layer (e.g. you call Workspaces "Sites" because you run physical-location software), capture the canonical-vs-label split in a deployment-level "Naming Reconciliation" note. **Never rename the canonical `key`.** Renaming the service after deployment is a migration; relabeling the UI is a one-line config change.

### A note on Workspaces specifically

Workspaces are intentionally **name-only** — a Workspace has a name, a parent Customer, and module installations. There is no `workspace_type` field, no fixed category enum. This is the Slack model: a Workspace's meaning is fully expressed by its name plus the modules its team uses. Naming reconciliation at the Workspace tier is therefore a UI-label decision only — it never implies a data-model variant.

---

## 6. Implementation checklist (per module)

Every module — foundational, business, third-party — follows the same checklist to claim Module Registry + Settings parity. Run through it in order; mark the module retrofit complete only when all ten rows are green.

| # | Step | Done when |
|---|---|---|
| 1 | Add the registry export at `src/moduleRegistry.js` on the BE. | All required fields (`key`, `label`, `registryVersion`, `attachmentScopes`, `dependencies`, `smiPath`, `ownedCollections`, `events`, `capabilities`, `settingsSchema`, `perRecordSettingsSchema`, `roles`) filled with concrete values. |
| 2 | Document the registry block and Module Settings block in the module's source-of-truth document. | Section 1 (Module Identity) holds the full registry block; Section 6.5 specifies Module Admins, Available Roles, Default Role, Capabilities, and Registry surfacing. |
| 3 | Define the module's role vocabulary (typically `{key}.admin` / `.member` / `.viewer`). | At least three roles defined, one marked Default, role IDs follow the `{key}.{role}` convention, present in `roles.defaults` on the registry. |
| 4 | Scaffold `/dashboard/{key}/settings` in the FE as a Server Component (no client interactivity in Phase A). | Page renders the five sections (Admins, Roles, Default, Capabilities, Registry) with hardcoded data. Phase A values labeled "Phase A — hardcoded" so reviewers know. |
| 5 | Add a gear button on the module's list/index page header linking to `/dashboard/{module}/settings`. | Visible on the list view; navigates to the settings page on click. |
| 6 | Use the simplified "Settings" label on per-record settings pages (route preserved at `/dashboard/{module}/{id}/settings`). | Page title, breadcrumb, button label, and pill all say "Settings". |
| 7 | Add a redirect at the **shell layer** for any legacy settings routes (e.g. `/dashboard/{module}/list/module-settings` → `/dashboard/{module}/settings`). | `curl` confirms `308` with the correct fully-qualified `Location` header. |
| 8 | Typecheck, commit, push the BE and FE for the module. | Both repos green in CI. |
| 9 | Visual smoke: load `/dashboard/{key}/settings` as an admin and verify all five sections render correctly. | Screenshot captured and attached to the module doc. |
| 10 | Update the module doc with the screenshot and mark Registry + Settings complete. | Module doc Section 1 (Registry) and Section 6.5 (Settings) both signed off. |

### Notes on individual steps

- **Step 4** — mirror the foundational tier's `/dashboard/{module}/settings` Server Component pattern. Phase A is read-only; do not ship "Edit" buttons that go nowhere. If a value is hardcoded, label it so reviewers can tell.
- **Step 7** — the redirect lives in the **portal shell's** routing config, not the module's own FE. A redirect defined inside the module FE strips the `/dashboard/{module}` prefix the shell uses to mount it, sending the browser to a 404. This failure mode was debugged extensively during early Sovereign Portal releases; do not re-litigate.
- **Step 9** — capture the screenshot at desktop resolution. Run the smoke in both light and dark modes if the deployment supports both.

---

## 7. Phase B sequencing (when you are ready)

Phase B is captured here for completeness; it is not a prerequisite for using Sovereign Portal. Run it when the deployment is ready to make Module Admins, Available Roles, and Default Role editable through the UI rather than code-defined.

1. Add the `moduleAdmins` schema (or `tenants.moduleAdmins[]` field — deployment's choice) and the bootstrap migration that seeds it from the first-user-of-tenant rule.
2. Seed Module Admins for every existing tenant.
3. Add `GET` / `PUT /v1/modules/{module}/admins` endpoints and wire the Settings page to use them instead of the hardcoded array.
4. Drop the operator bypass in `listMyCompanies` / `listWorkspaces` — Module Admins now provide the proper governance path.
5. Smoke the cross-tenant operator workflows; confirm operators only see what they have explicit access to.

Once Phase B is complete, the Settings page is a live editor of persisted module state and the operator-bypass shortcut is gone from the codebase.

---

## 8. Acceptance criteria

A module has achieved Module Registry + Settings parity when:

- The module's BE exports a complete `src/moduleRegistry.js` with every required field (`key`, `label`, `registryVersion`, `attachmentScopes`, `dependencies`, `smiPath`, `ownedCollections`, `events`, `capabilities`, `settingsSchema`, `perRecordSettingsSchema`, `roles`).
- The module's source-of-truth doc has a complete Section 1 Module Registry block mirroring that export, and a Section 6.5 Module Settings block specifying Module Admins (bootstrap rule), Available Roles (with one Default), Capabilities, and the Registry surfacing pattern.
- The module renders `/dashboard/{key}/settings` with the five standard sections (Admins, Roles, Default, Capabilities, Registry), in both light and dark modes.
- The module's list page has a gear button linking to its Settings page.
- The module's per-record settings page uses the simplified "Settings" label (route preserved).
- The module has the legacy `/dashboard/{module}/list/module-settings` → `/dashboard/{module}/settings` redirect at the shell layer, with a `curl`-verified 308 (if the deployment had any legacy route to redirect).
- The conformance suite passes `sovereign-portal verify` for the module.

---

## 9. Glossary

- **Module Registry** — the canonical metadata block every sovereign module exports from `src/moduleRegistry.js` (key, label, version, attachment scopes, dependencies, SMI path, owned collections, events, capabilities, settings schemas, default roles).
- **Module Settings page** — the page at `/dashboard/{module}/settings` that surfaces Module Admins, Available Roles, Default Role, and the Registry. Module-wide governance home.
- **Module Admin** — a user with module-wide governance rights for a specific module. Distinct from a role grant on a single record.
- **Default Role** — the role assigned to new invitees who arrive without an explicit role grant. Exactly one per module catalog.
- **Phase A / Phase B** — Phase A is FE-only with hardcoded data. Phase B replaces hardcoded data with BE-served, persisted, editable data.
- **SMI (Standard Module Interface)** — the broader contract every sovereign module conforms to. See `docs/smi-spec.md`.

---

## Source-of-truth pointers

- `docs/smi-spec.md` — the broader contract this pattern fits inside (especially §10–§12 on roles)
- `docs/permission-model.md` — the conceptual model these modules implement (four-tier scope, three-layer check, three-tier attachment scope)
- `docs/anti-patterns.md` — common mistakes when implementing the registry + settings pattern

---

*If you understand the Registry (the "what am I" question), the Settings page (the "who governs me" question), and the canonical-vs-label naming split, you can claim Registry + Settings parity for any new sovereign module on your first deploy. This is the simplest, highest-leverage structural pattern in the framework.*
