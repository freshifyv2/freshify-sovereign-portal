# Standard Module Interface (SMI) — v0.1

**The contract every Sovereign Portal module conforms to.**

---

| | |
|---|---|
| Status | v0.1 — public release |
| Audience | Developers building or auditing sovereign modules |
| Companion file | `types.ts` (full TypeScript contract, strict mode, compiles clean) |
| Conformance | `sovereign-portal verify ./your-module` |

---

## Why this document exists

"Sovereign module" is a marketing phrase until it is enforceable in code. This document is the enforcement. It defines, at the contract level, what a sovereign module is — what it exports, what context every request crosses, how it asks the framework permission questions, how it talks to other modules without coupling to them, and what guarantees it makes about its data on the way out.

The Users, Customers (`companies`), and Workspaces modules that ship with Sovereign Portal conform to this spec. The `module-template` starter conforms to this spec. The conformance suite verifies any module you build against it.

If the spec cannot cleanly describe the three foundational modules, the spec is wrong, not the modules. v0.1 was written against working code, not whiteboarded ahead of it.

**One more note before the sections begin.** The Users module owns identity **end-to-end** — both the pre-authenticated surface (signup, login, password reset, invite acceptance) and the post-authenticated surface (the user record, memberships, sessions, role assignments). There is no separate "Registration / Login" module. Identity is one sovereign module with two faces: a public-facing auth surface backed by the pluggable auth adapter (§8), and an authenticated admin/self-service surface backed by the rest of the SMI.

---

## What's in v0.1 (and what isn't)

**In v0.1 — nine sections**

1. Identity Context — how the framework represents who is calling
2. Authorization — module / function / data access decisions (including the three attachment-scope tiers)
3. Lifecycle — install, upgrade, workspace-created, uninstall, health, self-serve bootstrap, cascade deactivation
4. Module Descriptor — the single object every module exports
5. API Surface — how modules expose functions
6. Events — how modules talk without coupling
7. Data Ownership — sovereignty in storage
8. Auth Adapter — pluggable identity provider (Twilio OTP reference + swap-ins), pre-auth surface owned by the Users module
9. Supporting Types — schemas, logger, peer registry, extensible user-type pattern

**Locked in the v0.2 amendment** (shipped as part of v0.1's public release)

- §10 Role Catalogs — versioned, editable role records at Company / Workspace / Module tiers
- §11 Role Assignment — membership rows reference catalog `roleId`, never raw strings; highest rank wins
- §12 Role Settings UI — one framework-provided page, identical across every tier
- §13 Operator Composition — what the `operator: true` claim does (and does not) do
- §14 Conformance suite additions
- §15 Migration path

**Deferred to v0.3+**

- Layer 3 — module-owned granular per-function permission flags
- Capability-vocabulary extension mechanism
- Cross-module role templates ("Account Manager" across Projects + Tasks + Reports in one click)
- Audit-log schema for role catalog edits
- Observability conventions (logging / tracing shape)
- Rate-limit contract
- Postgres storage adapter (v0.1 ships Mongo only)
- Multi-region data residency

The v0.1 conformance suite ships runnable but minimal — enough to fail a module that does not expose a `moduleRegistry` entry at `/smi/<key>/registry`, does not declare its owned collections, reads another module's data directly, or omits `roles.defaults`.

---

## §1 — Identity Context

Every inbound request crosses the framework boundary carrying an `IdentityContext`. It carries four sovereign identity layers plus the active roles:

- `user` — the acting user (always present once authenticated)
- `company` — the Customer the user is acting on behalf of (a user can belong to many)
- `workspace` — the workspace within the Customer (a Customer can host many)
- `operator` — staff acting on behalf of a Customer (Freshify staff or the buyer's ops team)
- `roles` — role assignments active in this context, namespaced by layer

The four scope tiers — User, Customer, Workspace, Module record — are described in detail in `docs/permission-model.md`. The SMI is the contract that enforces them in code.

### Hard rules

- Modules **MUST NOT** read auth headers, JWTs, or session cookies directly. The auth adapter resolves an `IdentityContext`; modules see only the resolved context.
- `IdentityContext.workspace.companyId` **MUST equal** `IdentityContext.company.companyId`. The framework enforces on every request.
- Operator identity is always **additive** — operators never act anonymously, and `OperatorReason` is audit-logged on every action.
- Roles are namespaced by layer. A `company:admin` is a different role from a `workspace:admin`. The framework refuses to compare them across layers.

### Why "loose-coupled" not "strictly hierarchical"

A User belongs to many Customers. A Customer hosts many Workspaces. Modules compose against any of the three. There is no single tree. This is the architectural difference between Sovereign Portal and every multi-tenant framework that hard-codes `Tenant → User` as the only relationship.

### User → Customer attachment is not implicit

A user is never auto-attached to a Customer at Customer creation. Membership only exists when:

- The user **created** the Customer (self-serve signup path — they become Owner of that Customer; see §3 lifecycle and §11.4 below), or
- An existing Customer Admin/Owner **invited** them and they accepted, or
- An operator with `manage_users` on that Customer added them via the admin surface.

The Customers module does not write `user_company_memberships` rows on Customer creation beyond the single Owner row for the creating user. Bulk "attach a user list" UI lives in the **Users module**, not the Customers module.

---

## §2 — Authorization

Three layers, all expressed as decisions against an `IdentityContext`.

### 1. Module access (Layer 1)

Can this caller use this module at all? Called once per request, before any function dispatch. Returns `allow: true` or `allow: false` with a reason and a deny code.

### 2. Function access (Layer 2)

Can they call this specific function? Called per function invocation. Functions are named (`createOrder`, `viewInvoice`, `exportData`), and the policy receives the function name plus the input.

### 3. Data access

Of the data the function returns, what can the caller see? The policy returns a framework-neutral `ScopeFilter` (e.g. `{ kind: 'workspace', workspaceId: 'ws_123' }`), and the storage adapter translates that into the underlying query fragment.

### Why three layers and not one

Real-world permission errors come from blending these. "User can access Orders, can call `listOrders`, but only sees orders in their workspace" is three distinct decisions. The spec keeps them separate so each is independently testable. Conflated permission logic is the single most common source of multi-tenant data leaks; this is the structural defense against it.

### Composition (with v0.2 amendments)

A user can call functions inside a module only if **all three** of the following hold:

1. They have a Company role with at least `read` capability in the Customer containing the workspace.
2. They have a Workspace role with at least `read` capability in the workspace where the module is installed.
3. They have a Module role record for the `(workspaceId, moduleName)` pair.

Absence of any of the three → `403`, `reason: "layer1_denied"`. The module never sees the request.

### Attachment scope for module records (three tiers)

Individual records owned by a module are tagged with one of three **attachment scopes**, which the framework recognizes when evaluating data access:

| Attachment scope | Visible to | Typical use |
|---|---|---|
| `company` | Every Workspace in the Customer | Pricing Sets that apply across the whole Customer, master price books, company-wide policies |
| `workspace` | Only the specified Workspace | Workspace-local Locations, Workspace-only Pricing Sets, departmental settings |
| `location` | Only the specified Location within a Workspace | Location-specific overrides — a price that only applies at one warehouse, a rule for one site |

The `ScopeFilter` returned by the Layer 3 data-access decision (§2.3) can include `attachmentScope`. Modules SHOULD honour all three tiers when storing records that can sensibly be shared upward. Modules that have no notion of company-wide records (e.g. an internal ticketing module that is always workspace-scoped) MAY ignore the `company` and `location` tiers entirely — declaring this in the descriptor.

---

## §3 — Lifecycle

Every module exposes five hooks. The framework calls them; the module owns the implementation.

| Hook | When called | Idempotency |
|---|---|---|
| `onInstall(ctx)` | Once per Customer when the module is installed | MUST be idempotent |
| `onUpgrade(ctx, from, to)` | When the module version changes | MUST be idempotent |
| `onWorkspaceCreated(ctx)` | When a new workspace is created in a Customer that has this module | MUST be idempotent |
| `onUninstall(ctx)` | Before removal. Exports data, then deletes. | MUST NOT throw |
| `health()` | Framework polls. Failure marks the module degraded. | Read-only |

### Self-serve bootstrap path (Customers + Workspaces)

The Customers and Workspaces modules implement an additional, framework-visible **self-serve onboarding** path that the framework wires into the auth adapter's `completeSignIn` callback:

1. A new user signs up via the Users module.
2. They create a Customer. The Customers module writes a single `user_company_memberships` row with the Owner role, `assignedAt = now()`, `assignedByUserId = <self>`. No other rows.
3. They create a Workspace inside the Customer. The Workspaces module writes a single `user_workspace_memberships` row with the Workspace Owner role, same pattern.
4. They invite teammates. Invites are owned by the **Users module** (see §8 and `users-conformance.ts`). Acceptance writes the appropriate membership row.

This is the Slack model. The framework requires no manual seeding to be operable post-install. Operators may still bootstrap Customers and users via admin endpoints, but the self-serve path is the default and is the one the reference portal demonstrates.

### Cascade deactivation

Deactivating a Workspace MUST first verify that all dependent module records (Locations, Orders, Pricing Sets, etc.) are themselves deactivated. The Shell app polls each installed module's `POST /smi/<key>/dependency-status` endpoint with `{ scopeKind, scopeId }`. Each module answers `{ canDeactivate, blockers: [...] }`. If any module returns `canDeactivate: false`, the deactivation is refused with a structured error listing the blockers.

This rule applies symmetrically to Customer deactivation (which blocks until all Workspaces are deactivated). Every module that holds records against a scope MUST implement `dependency-status` for `scopeKind: 'customer'` and `scopeKind: 'workspace'`.

**Distinct from per-record liveness.** A separate endpoint, `POST /smi/<key>/record-status` with `{ recordType, recordId }`, answers "is this specific record still alive?" Peers holding a foreign key into another module's records call `record-status` (per-record), not `dependency-status` (per-scope cascade). The two contracts are deliberately different and named differently.

### The uninstall contract is non-negotiable

Every sovereign module MUST export the Customer's data on uninstall (location returned in `UninstallReport.exportLocation`) and then delete it. This is part of why Sovereign Portal can credibly say "owned platform" — Customers can leave with their data, and the framework can prove it ran.

---

## §4 — Module Registry

Every module exposes exactly one registry entry at `GET /smi/<key>/registry`. This is the framework's entry point — registration, loading, routing, conformance checks all key off this object. There is no shared runtime package and no required import; the registry is plain JavaScript (or any language emitting equivalent JSON over HTTP).

```js
// src/registry/moduleRegistry.js — the canonical shape
module.exports = {
  key: "users",                          // stable identifier — never rename
  label: "Users",                        // human-readable
  registryVersion: "1.0.0",              // bump when shape changes

  // Which scope tiers a record in this module can attach to.
  // [] means the module owns identity itself (Users, Customers, Workspaces).
  attachmentScopes: [],

  dependencies: [],                      // peer modules this one reads
  smiPath: "/smi/users",                 // where this module's SMI lives
  ownedCollections: [
    "users",
    "user_company_memberships",
    "user_workspace_memberships",
    "invites",
    "auth_tokens",
    "password_resets",
  ],

  events: {
    publishes: [
      "users.created",
      "users.invited",
      "users.invite_accepted",
      "users.deactivated",
    ],
    subscribes: [],
  },

  capabilities: [
    { key: "core_crud",      label: "Create/read/update users",   togglable: false, default: true },
    { key: "invites",        label: "Email/SMS invites",          togglable: true,  default: true },
    { key: "password_reset", label: "Password reset flow",        togglable: true,  default: true },
  ],

  settingsSchema: {
    inviteExpiryDays:   { type: "number",  default: 7, min: 1, max: 90 },
    requireEmailVerify: { type: "boolean", default: true },
  },

  perRecordSettingsSchema: {
    userType: { type: "enum", values: ["operator", "customer", "agent"] },
  },

  // v0.2 — see §10
  roles: {
    defaults: [ /* ModuleRoleDefault[] */ ],
  },
};
```

The registry IS the contract. Anything not declared here is invisible to the framework — and to the conformance suite. If a module emits an event that is not in `events.publishes`, the framework rejects it at runtime. If it reads a collection that is not in `ownedCollections` (and is not owned by a declared peer), the storage handle throws.

### Field reference

| Field | Purpose |
|---|---|
| `key` | Stable identifier. Used as foreign key in peers' records. Pick once, never rename. |
| `label` | Human-readable name for operator UIs. |
| `registryVersion` | Semver. Bump when peers must adapt. |
| `attachmentScopes` | Subset of `["company", "workspace", "location"]`. Empty `[]` for identity modules whose records do not attach to scopes. |
| `dependencies` | Peer module keys this one calls. Peer registry refuses to resolve any key not listed. |
| `smiPath` | Conventionally `/smi/<key>`. Where this module exposes its SMI surface. |
| `ownedCollections` | Database collections this module owns. Cross-module reads through SMI, never through storage. |
| `events.publishes` | Named events this module emits. Emitting an undeclared event throws. |
| `events.subscribes` | Named events from peers this module subscribes to. |
| `capabilities` | Operator-facing on/off switches. `togglable: false` means structural (cannot be disabled without forking). |
| `settingsSchema` | Module-wide settings per Customer. Drives the FE module-settings page. |
| `perRecordSettingsSchema` | Per-record overrides. Drives the FE gear-icon settings on each record. |
| `roles.defaults` | v0.2. Default role catalog the framework imports at install. See §10. |

### Why fields, not a typed package

Earlier drafts of this spec referenced a `ModuleDescriptor` type imported from a hypothetical `@sovereign-portal/core` package. That package does not exist and will not exist in v1. The registry shape is documented here and demonstrated in `sovereign-module-template-be/src/registry/moduleRegistry.js`. Any module that emits an object matching this shape over `/smi/<key>/registry` is sovereign-compliant, regardless of language or framework. If a shared runtime package is ever useful (for example, to generate TypeScript types from the registry shape), it can be added as a non-required convenience.

### `roles.defaults` (v0.2 amendment)

`roles.defaults` is required. A registry without it fails the v0.2 conformance suite. Each entry conforms to `ModuleRoleDefault` (see §10). Exactly one default MUST declare `isAutoAssigned: "owner_on_create"`. See §10.4.3 for the baseline catalog the framework imports when a module is installed.

---

## §5 — API Surface

Modules expose two distinct surfaces over HTTP:

**SMI surface** at `/smi/<key>/*` — stable, versioned by `registryVersion`, intended for peers, the FE, and agent sidecars. Includes at minimum:

- `GET /smi/<key>/registry` — returns the registry entry above
- `POST /smi/<key>/record-status` — per-record liveness (see §3)
- `POST /smi/<key>/dependency-status` — per-scope cascade gate (see §3)
- `GET /smi/<key>/health` — liveness probe

**Domain surface** at `/<noun>/*` (e.g. `/tickets/*`, `/orders/*`) — the module's CRUD and business logic. NOT considered stable across minor versions. The FE may call these endpoints; peers MUST NOT.

A third optional surface, `/agent/*`, exists when a module has an agent sidecar. Service-principal auth only. See §16 — Agent Sidecars.

### Cross-module calls go through the peer registry

A module reads peer state by calling the peer's SMI endpoints, never by importing a peer's models or querying a peer's database:

```js
const { recordStatus } = require('./registry/peerRegistry');

// I hold a userId from the Users module. Is that user still active?
const status = await recordStatus('users', 'user', submittedByUserId);
if (!status.active) {
  return res.status(400).json({ error: 'user no longer active' });
}
```

Modules can only resolve peers they declared in `dependencies`. The peer registry refuses to resolve any other key. This makes the dependency graph explicit and auditable — you can render it from the registry entries alone, without running the code.

---

## §6 — Events

Events are how modules talk without coupling. The framework routes them; subscribers do not know who published.

### Publishing

```ts
await ctx.emit({
  name: "users.created",
  payload: { userId, email, companyId },
  emittedBy: ctx.identity,
  emittedAt: new Date().toISOString(),
  eventId: crypto.randomUUID(),
});
```

The framework type-checks `payload` against the descriptor's `publishes` array. Emitting an undeclared event throws.

### Subscribing

Subscribers handle events with the same `ModuleCallContext` shape as functions. Errors retry with exponential backoff; after the retry budget is exhausted, the event lands in a dead-letter queue the operating team monitors.

### Idempotency

Every event has a unique `eventId`. Handlers MUST be idempotent on `eventId` — the framework may redeliver. The conformance suite includes a redelivery test.

### Why events at all

Sovereignty falls apart the moment Module A reaches into Module B's database to react to a change. Events make reactions explicit, declared, and replayable. They are the architectural enforcement mechanism for "modules are first-class peers."

---

## §7 — Data Ownership

**Sovereignty rule:** a module's data is owned by that module. Other modules MUST NOT read it directly — they call the owning module's API.

The `ModuleStorage` handle the framework gives each module is scoped to that module's own schemas. Asking for `storage.collection('orders')` from inside the Users module throws. The schema registry knows who owns what.

This is **enforceable**. The conformance suite runs a static check: it walks every module's source for `storage.collection(...)` calls and verifies the named schema is owned by that module. Cross-module data reads fail the check.

The escape hatch is the peer registry, and the only thing the peer registry lets you call is another module's **declared API functions**. You cannot read another module's storage. Ever.

**Practical payoff.** The schema-ownership rule is what makes feature removal safe in practice. When a deployment turns off invites (or any other sub-feature of a sovereign module), no other module breaks — because the conformance suite already proved no other module was reaching into the `invites` collection. The boundary is enforceable, not aspirational. See the README's "Turning things off" patterns.

---

## §8 — Auth Adapter

The auth adapter is the only thing in the framework that knows about the outside world's identity system. It produces an `IdentityContext` from an inbound request; everything downstream works against that resolved context.

v0.1 ships with a **Twilio OTP reference adapter**. It implements the full `AuthAdapter` interface — phone-number sign-in, OTP verification, session token management. You can demo Sovereign Portal end-to-end with nothing but a Twilio account.

You swap in your own identity provider by implementing `AuthAdapter`. The framework guarantees that any adapter satisfying the interface plugs in cleanly.

| Adapter | Status |
|---|---|
| Twilio OTP | v0.1 (ships now). SMS-only, intentionally minimal. |
| Auth0 | v0.2 target |
| Okta | v0.2 target |
| Clerk | v0.3 target |
| Cognito | v0.3 target |
| Custom SAML / OIDC | v0.4 target |

### Hard rule

The adapter is **the only place** in the entire framework that touches headers, cookies, JWTs, or external identity-provider SDKs. Every module is portable across adapters because every module only sees `IdentityContext`. You can swap auth without rewriting a single module.

The adapter interface has four methods: `resolve(request) → IdentityContext`, `startSignIn`, `completeSignIn`, `signOut`. That's it. Adapters are typically 100–300 lines.

---

## §9 — Supporting Types

- **Owned collections** — declared in `moduleRegistry.ownedCollections`. Each is a string naming a collection this module owns. The framework's storage handle throws on access to undeclared collections, and refuses cross-module access entirely — peers reach data through SMI, not through storage.
- **Logger** — framework-provided. Carries the active `IdentityContext` and module name automatically. Modules MUST NOT instantiate their own loggers; structured logs depend on the framework-attached context.
- **Peer Registry** — the local helper that calls `/smi/<peerKey>/*` endpoints (see `peerRegistry.js` in the reference template). Returns parsed JSON, or a conservative fallback if the peer is unreachable. Throws if `peerKey` is not in `dependencies`.

### Extensible user-type pattern (Users module)

The core `users` schema carries a single typed `user_type` field. v0.2 ships with one value — `"standard"` — and the framework treats it as an opaque tag for filtering and presentation, never as an authorization input. (Authorization always flows through the role catalog.)

Modules that need to attach role-shaped or domain-specific data to a subset of users — e.g. "this user is also a driver" or "this user is also a sub-contractor representative" — SHOULD add their own side table keyed by `userId`, not extend the core `users` schema. The Users module never grows new columns for downstream concerns. This is enforced by the conformance suite's schema-ownership check (§7): downstream modules must own their own attributes.

---

## §10 — Role Catalogs (v0.2 amendment)

A **role catalog** is a versioned, editable list of role records scoped to one of three tiers: **Company**, **Workspace**, or **Module**. The catalog is the framework's source of truth for what roles exist in that scope. Membership rows reference catalog entries by `roleId`; they never embed role names directly.

Catalogs are **per-platform-instance**. The team that deploys Sovereign Portal owns and edits their own catalogs. Two deployments may have completely different role sets. The framework ships a sensible default catalog with every fresh install; you fork it as you grow.

### 10.2 — Role record shape

```ts
interface RoleRecord {
  roleId: string;             // rol_xxx — stable, framework-generated
  scope: RoleScope;           // "company" | "workspace" | "module:<name>"
  scopeId?: string;           // company/workspace id, or workspace+module pair
  key: string;                // stable machine name, immutable post-create
  label: string;              // editable display label
  description: string;        // editable, surfaced in Role Settings UI
  rank: number;               // 0..100, higher = more power
  isSystem: boolean;          // true = ships with framework or module
                              //   editable, never deletable
  isAutoAssigned:
    | "owner_on_create"       // user who creates the scope gets this role
    | null;
  capabilities: Capability[]; // see §10.3
  createdAt: string;
  updatedAt: string;
}
```

**Framework-enforced rules:**

- `roleId` is generated by the framework on create. Modules and application code MUST NOT construct `roleId`s.
- `key` is immutable post-create. The framework rejects edits that change `key`.
- Exactly one role per catalog may have `isAutoAssigned = "owner_on_create"`.
- `isSystem` records can have `label`, `description`, `rank`, and `capabilities` edited. They cannot be deleted, and `key` cannot change.
- Two roles may share a `rank` value; the framework breaks ties by `createdAt` ascending for "highest rank wins" decisions.

### 10.3 — Capability vocabulary (v0.2)

A deliberately small, platform-standard set. Capabilities are coarse — they describe what a role broadly can do at the layer it applies to. Per-function granularity is Layer 3 and stays out of scope for v0.2.

| Capability | Meaning |
|---|---|
| `read` | View records in scope |
| `write` | Create and edit records in scope |
| `manage_users` | Add/remove users from the scope |
| `manage_settings` | Edit non-role settings in scope |
| `manage_roles` | Edit the role catalog for this scope |
| `transfer_ownership` | Move the Owner role to another user |
| `delete` | Delete the scope itself |

You may not invent new capability strings in v0.2. v0.3 will add an extension mechanism.

### 10.4 — The three catalog tiers

#### 10.4.1 — Company catalog (default)

| Key | Label | Rank | Auto-assign | Capabilities |
|---|---|---|---|---|
| `owner` | Owner | 100 | `owner_on_create` | all |
| `admin` | Admin | 80 | — | `read, write, manage_users, manage_settings, manage_roles` |
| `member` | Member | 30 | — | `read, write` |
| `viewer` | Viewer | 10 | — | `read` |

#### 10.4.2 — Workspace catalog (default)

| Key | Label | Rank | Auto-assign | Capabilities |
|---|---|---|---|---|
| `owner` | Owner | 100 | `owner_on_create` | all |
| `manager` | Manager | 70 | — | `read, write, manage_users, manage_settings` |
| `member` | Member | 30 | — | `read, write` |
| `viewer` | Viewer | 10 | — | `read` |

There is intentionally no Admin tier at the Workspace layer. Governance happens at the Company; Workspaces are operational units. Manager is the highest non-owner.

#### 10.4.3 — Module catalog (baseline default — overridable per module)

If a module declares no `roles.defaults`, the framework imports this baseline:

| Key | Label | Rank | Auto-assign | Capabilities |
|---|---|---|---|---|
| `owner` | Owner | 100 | `owner_on_create` | all |
| `manager` | Manager | 70 | — | `read, write, manage_users, manage_settings` |
| `member` | Member | 30 | — | `read, write` |
| `viewer` | Viewer | 10 | — | `read` |

**Module Owner semantics:**

- Auto-assigned to whichever user installs the module in a workspace. This may or may not be the Workspace Owner — they can be different people.
- Exactly one Owner per `(workspaceId, moduleName)` pair. Framework-enforced uniqueness.
- Transferable to any user holding a Workspace role of Member or higher in that workspace.
- Owning a module in workspace X confers no role in workspace Y. Module ownership is strictly scoped.
- On module uninstall, all module-role records for that `(workspace, module)` pair are deleted with it.

### 10.5 — Terminology lock

v0.2 uses **"Owner"** at all three tiers (Company, Workspace, Module). The word "Creator" is retired everywhere. The framework, the descriptor, the UI, and the documentation all say Owner. Developers learn the concept once.

Ownership is always transferable. Ownership records are always audit-logged. There is always exactly one Owner per scope instance.

---

## §11 — Role Assignment

### 11.1 — Membership rows reference catalogs

v0.1 used hardcoded role strings on membership rows. v0.2 replaces them with `roleId` foreign references.

```ts
interface UserCompanyMembership {
  userId: string;
  companyId: string;
  roleId: string;             // → role catalog (scope="company")
  assignedAt: Date;
  assignedByUserId: string;
}

interface UserWorkspaceMembership {
  userId: string;
  companyId: string;          // denormalized for scope enforcement
  workspaceId: string;
  roleId: string;             // → role catalog (scope="workspace")
  assignedAt: Date;
  assignedByUserId: string;
}

interface UserModuleMembership {
  userId: string;
  workspaceId: string;
  moduleName: string;
  roleId: string;             // → role catalog (scope="module:<name>")
  assignedAt: Date;
  assignedByUserId: string;
}
```

### 11.2 — Highest rank wins

A user may hold multiple roles in the same scope. When evaluating capabilities, the framework computes the **effective role** as the one with the highest `rank` value.

Tie-break: when two roles share a rank, the earlier `assignedAt` wins. Deterministic and audit-stable.

### 11.3 — Function access (Layer 2) composition

Once Layer 1 passes (see §2), the function-access decision computes the user's effective capabilities at each layer (Company, Workspace, Module) and checks the function's declared `requiredCapabilities` against the union. v0.2 keeps `requiredCapabilities` optional; functions without one default to `read`.

### 11.4 — Self-serve Owner assignment

The Customer or Workspace creation flow MUST write the Owner membership row in the same transaction as the scope itself. The framework provides `framework.scope.createWithOwner(scopeKind, attrs, userId)` which both modules call. There is exactly one Owner per scope at creation time; subsequent ownership changes go through `transferOwner(scopeKind, scopeId, fromUserId, toUserId)` which is audit-logged with reason and timestamp.

When a self-serve user signs up but does not yet create a Customer, they exist in the Users module as an unattached user with no memberships. They see only the "Create Customer" call to action until they either create one or accept an invite. There is no orphan-user error state.

---

## §12 — Framework Role Settings UI

v0.2 specifies **exactly one Role Settings page UI**, provided by the framework. Modules do not build their own. The same page renders against any catalog tier — Company, Workspace, or Module.

### Where it lives

- Company catalog: `/dashboard/companies/:companyId/settings/roles`
- Workspace catalog: `/dashboard/workspaces/:workspaceId/settings/roles`
- Module catalog: `/dashboard/:moduleName/settings/roles` — auto-generated by the framework when the module registers. The module owns no UI code for this page.

### Page contract

Every Role Settings page renders the same layout regardless of tier:

- **Header** — scope name (Customer / Workspace / Module), current user's role in this scope, capability summary.
- **Catalog table** — `roleId`, `key` (readonly), `label`, `description`, `rank`, capability checkboxes (the 7 v0.2 capabilities), `isSystem` badge, `isAutoAssigned` badge.
- **Inline edit** — `label` / `description` / `rank` / `capabilities`. Save is per-row. `isSystem` rows show "Cannot delete" instead of a delete button.
- **Add role** — opens a row in create mode. New roles default to `isSystem=false` and can be deleted.
- **Reset to defaults** — re-runs the module's `roles.defaults` import (or framework defaults for Company/Workspace). Confirms with a modal listing exactly what will change.
- **Audit footer** — "Last edited by `<user>` at `<timestamp>`" per row.

### Module-agnostic implementation

The Role Settings page reads via a single framework function — `getRoleCatalog(scope, scopeId)` — and writes via `upsertRoleRecord` and `deleteRoleRecord`. These are part of the framework's public surface, not any module's API. Modules do not implement them.

---

## §13 — Operator Composition

The `operator: true` claim on an `IdentityContext` does three things, and only three things.

### What the operator claim does

1. **Tenant switcher contents.** An operator sees a top-level "Operator view (all tenants)" entry plus every Customer they hold an actual membership row in. A non-operator sees only the Customers they hold membership rows in.
2. **Audit-log enrichment.** Every write performed under the operator JWT is audit-logged with `operatorReason` (one of: `support`, `incident`, `audit`, `migration`, `impersonation`).
3. **Operator view virtual scope.** In "Operator view (all tenants)", list endpoints fall back to admin variants (e.g. `/v1/admin/companies` instead of `/v1/companies`) that return cross-tenant directories.

### What the operator claim does NOT do

- It does **NOT** auto-grant any role in any Customer, Workspace, or Module.
- It does **NOT** bypass Layer 1, Layer 2, or Layer 3 (when Layer 3 ships).
- It does **NOT** confer capabilities. Inside a specific tenant, an operator acts with their actual assigned roles per layer — like any other user.

The operator claim is purely an **observability and routing concern**. It changes what UI surfaces are offered (tenant switcher, audit fields) and how writes are logged (`operatorReason`). It is never an authorization input.

### Switching into a tenant

When an operator selects a Customer from the tenant switcher, the framework sets an `active_tenant` cookie that scopes subsequent requests to that Customer. The JWT is not re-issued. Their effective permissions in that Customer come from the membership row(s) that link them to it — the operator claim only ensures the option was offered.

### Cross-tenant ("Operator view") permission model

In the "Operator view (all tenants)" virtual scope, the framework applies a simpler rule: **operator + read-only**. The view shows lists across tenants but does NOT permit writes from this scope. To take action inside a specific tenant, the operator MUST first switch into that tenant.

Rationale: prevents accidental cross-tenant writes (e.g. editing a user while in operator view and not realizing which tenant they belong to). Writes go through tenant-scoped routes only.

---

## §14 — Conformance Suite

The conformance suite ships as a CLI:

```bash
sovereign-portal verify ./my-module
```

CI integrators hook it as a pre-merge check.

### v0.1 checks

- Module exposes a single registry entry at `GET /smi/<key>/registry`.
- Every schema the module reads is owned by the module or by a declared peer.
- Every event the module emits is listed in `events.publishes`.
- All five lifecycle hooks are implemented.
- All three permission decisions are implemented.
- `onUninstall` returns an `UninstallReport` and does not throw on the happy path.
- Auth adapter (if shipped with the module) satisfies the `AuthAdapter` interface.
- Event handlers are idempotent under redelivery.

### v0.2 additions

- `moduleRegistry.roles.defaults` is present.
- Exactly one default has `isAutoAssigned: "owner_on_create"`.
- Every capability listed is in the v0.2 vocabulary.
- `key` values in `roles.defaults` are unique.
- Membership-row writes use `roleId`, not legacy role strings.

A module that passes v0.1 but fails any v0.2 check is **v0.1-conformant but not v0.2-conformant.**

---

## §15 — Migration Path (v0.1 → v0.2)

Sovereign Portal is pre-1.0. v0.2 is breaking. The migration path is mechanical but mandatory before any v0.2-conformant module is installed.

### Step 1 — Install the role catalog store

The framework gains one new schema: `role_catalogs`. The Users sovereign module owns it (since the catalog is part of identity/authorization). Migration runs a one-time installer that creates the schema and writes the Company + Workspace default catalogs (§10.4.1, §10.4.2).

### Step 2 — Migrate membership rows

Existing `user_company_memberships` rows have `role: "admin" | "member"`. The migration:

1. Resolves the Company catalog to specific `roleId`s for `key="admin"` and `key="member"`.
2. For each membership row, sets `roleId` based on the legacy role string. Drops the `role` column.
3. For `owner_on_create`: any Company where exactly one membership row has `role="admin"` AND that user matches the Company's `ownerUserId` is upgraded to the catalog's Owner role.

Same procedure for `user_workspace_memberships` against the Workspace catalog.

### Step 3 — Re-install every module

Modules installed before v0.2 must run their `onInstall(workspaceId)` hook again to populate their module catalog:

```bash
sovereign-portal reinstall --all
```

For modules that do not yet declare `roles.defaults` (v0.1-only modules), the framework applies the §10.4.3 baseline catalog and emits a warning.

### Step 4 — Verify

Run the v0.2 conformance suite against every installed module. Failures block the cutover.

---

## Worked example — the Users module conforms

The Users module is the most important conformance test: if the spec cannot cleanly describe a working Users module, the spec is wrong.

**Conformance pass:**

- Exposes a single `moduleRegistry` over `GET /smi/<key>/registry`
- Declares all schemas it owns (`users`, `user_company_memberships`, `user_workspace_memberships`, `user_module_memberships`, `role_catalogs`, `auth_tokens`, `invites`, `password_resets`)
- Does not read any schema it does not own
- Declares all events it publishes (`users.created`, `users.invited`, `users.invite_accepted`, `users.deactivated`, `users.password_reset_requested`)
- Implements all five lifecycle hooks
- Implements all three permission decisions
- Implements `POST /smi/<key>/dependency-status` for both `scopeKind: 'customer'` and `scopeKind: 'workspace'` (§3 cascade)
- Implements `POST /smi/<key>/record-status` for every `recordType` the module owns (§3 per-record liveness)
- `onUninstall` returns an `UninstallReport` and does not throw
- Declares `roles.defaults` with exactly one `owner_on_create` entry
- Owns the pre-authenticated surface (signup, login, password reset, invite acceptance) backed by the auth adapter (§8)

Customers (`companies`) and Workspaces conform identically. Same shape, same hooks, same registry, with their own self-serve `createWithOwner` flows wired (§3, §11.4). **They are not framework primitives. They are sovereign modules.** The framework eats its own dogfood.

The Workspaces module v0.2 reference carries a `name` field and a parent `companyId`, plus the standard lifecycle hooks — nothing else. There is no `workspace_type` column. Workspace meaning is fully expressed by name + membership + module installations, not by a typed classifier.

---

## §16 — Agent Sidecars

A sovereign module is **two or three repos**:

- BE — owns schema, runs the SMI surface, runs the three-layer permission check
- FE — operator UI, registry-driven
- Agent (optional) — the module's intelligence layer

Agents are not a separate concept bolted onto the framework. They are the cognitive half of a module that happens to need one. Pricing without a Pricing Agent is just CRUD; with the agent it becomes adaptive. Same for Inventory (reorder suggestions), Orders (fraud detection), Support (classification and reply drafting).

Foundational modules (Users, Customers, Workspaces) do not have agents. Pure-CRUD domain modules do not need them. Modules where reasoning over the data adds value do.

### Three rules every agent obeys

**1. Bonded to a parent.** An agent serves exactly one module. There is no platform-wide AI that knows about everything. Pricing Agent operates inside Pricing; Inventory Agent inside Inventory. If a behavior needs to span modules, the modules emit events and a peer-bonded agent on the receiving side reasons over them.

**2. No schema.** The agent has no database connection. Its memory lives on the parent module's records (commonly an `agentMetadata` sub-document) and is written through the parent's `/agent/*` hooks, never directly. Grep the agent repo: `mongoose` should not appear in `package.json`.

**3. Service-principal auth.** The agent authenticates to its parent BE with a long-lived service-principal token, not a user JWT. It has no user-scoped permissions; every action must declare the scope it is operating in (`customerId` + optional `workspaceId`), and the parent BE validates the agent is allowed to act in that scope.

### Two patterns every agent demonstrates

Agents do two distinct things, and the patterns have different shapes:

**Advisory.** Operator asks "draft a reply," "summarize this thread," "suggest a price." Latency budget is seconds; reasoning quality matters; the human approves before any external side effect.

**Inline decisioning.** A new record arrives; the agent classifies, routes, or adjusts in real time before the operator (or the customer) ever sees it. Latency budget is sub-second; the agent decides; a deterministic fallback runs if the LLM is slow or unavailable. **The fallback existing is non-negotiable.** An agent that takes down the parent module when the LLM is slow is not sovereign.

The `sovereign-module-template-agent` reference implementation ships both patterns side by side. New agents must demonstrate both.

### Parent BE contract for agents

A module that has an agent exposes `/agent/*` routes for the agent to write through. These routes:

- Use service-principal auth, not user auth
- Validate the agent is operating in a scope the parent recognizes
- Are gated by the same capability check as any other write. If `agent_drafts` is disabled in the Customer's settings, `POST /agent/draft-reply` returns 403 — the agent does not need to know
- Write only into the `agentMetadata` field of the parent's records, never into separate agent-owned collections

If a Customer disables the agent capability entirely, the parent module continues working without the agent. This is the proof that the agent is loose-coupled and not load-bearing.

### Capability vocabulary for agents

The agent's writes are gated by capabilities declared in the parent module's registry. Conventional capability keys:

- `agent_inline_classify` — the inline pattern is allowed to run
- `agent_drafts` — the advisory pattern is allowed to produce drafts
- `agent_auto_act` — the agent's inline output is applied without operator review (default: false; most deployments require operator review)

### Conformance

A module that ships an agent passes agent-conformance only if:

- The agent repo has no Mongoose/Sequelize/Prisma/storage dependency
- All agent writes go through the parent's `/agent/*` routes
- The inline pattern includes a heuristic fallback that runs without the LLM
- Disabling `agent_drafts` (or equivalent) returns 403 from the parent BE, not just a hidden button in the FE
- The agent's service principal is allow-listed only for the parent module's SMI surface

---

## What this commits the framework to

- **The conformance suite is the contract.** If the spec says X and the suite does not verify X, the suite is wrong.
- **The reference modules conform.** Users, Customers, Workspaces, and `module-template` all pass `sovereign-portal verify` at every release tag.
- **Breaking changes between minor versions require a migration script.** v0.1 → v0.2 ships with `sovereign-portal reinstall --all`. Future breaking changes will ship with their own command.

## What this does NOT commit to

- **A specific storage engine.** v0.1 has a Mongo adapter; Postgres lands when the demand is there.
- **A specific runtime.** Node.js is assumed for v0.1; the spec is engine-neutral in principle.
- **A specific deployment shape.** Modules can run as separate services or as a monolith. Both are supported.
- **A specific frontend.** The reference portal is React/Next.js, but the SMI is a backend contract. You can build any UI on top.

---

## Open questions for v0.3

- Capability vocabulary extension — when a deployment legitimately needs a new capability string, how do they declare and propagate it without forking the framework?
- Layer 3 storage shape — per-module table or a generic `granular_permissions` table keyed by `(moduleName, functionName, userId)`?
- Role catalog versioning — when a default role is edited, does the framework track edit history? If so, in what schema and for how long?
- Cross-workspace module roles — for "an Account Manager who is Owner in 30 workspaces at once," do we need a "role template" concept above the catalog tier?
- Operator delegation — can an operator temporarily grant another operator their permissions on a specific Customer for, say, 24 hours? New role with `expiresAt`, or new claim type?
- Module marketplace — third-party modules become possible. Out of scope for v0.1 but worth keeping the spec narrow enough that the marketplace is reachable from here.

---

## Source-of-truth pointers

- `sovereign-module-template-be/src/registry/moduleRegistry.js` — the canonical registry shape, as runnable code
- `sovereign-module-template-be/src/smi/routes.js` — the SMI surface every module exposes (`registry`, `record-status`, `dependency-status`, `health`)
- `sovereign-module-template-agent/` — the canonical agent sidecar shape (no schema, two patterns, fallback)
- `docs/permission-model.md` — the conceptual model the SMI implements ("Four-Tier Scope, Three-Layer Check")
- `docs/module-registry-and-settings.md` — the Module Registry + Settings spec the framework Settings UI implements
- `docs/anti-patterns.md` — the mistakes we made so you do not have to

---

*End of SMI v0.1 (incorporating v0.2 amendment).*
