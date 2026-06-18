# Sovereign Portal Permission Model

**Four-tier scope hierarchy. Three-layer permission check. One Owner per scope. Configuration not code.**

---

This document is the "why." The SMI spec (`docs/smi-spec.md`) is the "what." Read this one first if you are trying to understand the architecture before reading the contract that enforces it.

The Sovereign Portal permission model is the shape of identity, scope, and authorization in every sovereign module. It is the structural answer to a single question: **how does a SaaS platform support tens of thousands of customers, each with their own teams, their own sub-organizations, and their own opinions about who can do what, without becoming a nest of conditional logic that nobody can refactor?**

The answer has two pieces, and conflating them is the most common mistake — so we keep them strictly separate.

## The two pieces

**1. The scope hierarchy** — the *containers* data lives inside. Four tiers:

| Tier | What it represents | Examples |
|---|---|---|
| 1. **Users** | The acting human identity | Person logging in |
| 2. **Customers** (`companies`) | The organization the user is acting on behalf of | A buyer's company, an agency client |
| 3. **Workspaces** | A scoped operational unit inside a Customer | A department, a project, a region |
| 4. **Module records** | The actual rows owned by any first-class module | Orders, Pricing Sets, Locations, Invoices |

Every record in any module ultimately belongs to a Workspace, which belongs to a Customer. The user's session token carries identity at the upper three tiers (`user_id`, `company_id`, `workspace_id`). The module reads its own records at the fourth.

**2. The permission check** — the *gates* every request passes through. Three layers:

| Layer | What it asks | What it returns |
|---|---|---|
| 1. **Module access gate** | Does this user have any role in this module at all, in this scope? | yes/no |
| 2. **Module-level role** | What role do they hold at the relevant scope (Customer or Workspace)? | role record |
| 3. **Granular permission** | Does that role grant this specific action on this specific record? | allow/deny |

The four-tier scope hierarchy is the *shape of the data*. The three-layer permission check is the *shape of the decision*. Each layer runs against the appropriate scope tier. Mixing the two — for example, calling Modules "the fourth layer" — is what produces the conditional-logic nest the model is built to avoid.

`is_operator` is an observability flag, not a permission tier. It drives the "Operator" badge in module Registries and the operator-reason field in audit logs. It does not bypass any check.

---

## Why "loose-coupled" not "strictly hierarchical"

Most multi-tenant frameworks bake in a tree: `Tenant → User`, period. One user belongs to one tenant. Maybe a "team" inside the tenant. The framework's data model assumes the tree, the routes assume the tree, the UI assumes the tree, and the moment a real customer asks for "Sarah needs to see orders across our two acquired subsidiaries," the framework breaks.

Sovereign Portal is shaped for that real-world ask from day one.

- **A user can belong to many Customers.** Sarah works at both Acme Corp and Acme Subsidiary. One login, two memberships, two role contexts.
- **A Customer can host many Workspaces.** Acme Corp has a Workspace for Operations, one for Finance, one for the West Coast team.
- **Modules compose against any of the upper three scopes.** The Orders module scopes by Workspace. The Billing module scopes by Customer. The Audit module scopes by User. No single tree forces them all into the same shape.

There is no single hierarchy. There is a **graph of memberships and module installations**, and the framework computes permission decisions over that graph at every request.

This is the architectural difference between Sovereign Portal and every multi-tenant SaaS framework that hard-codes `Tenant → User` as the only relationship.

---

## Scope Tier 1 — Users

The user is the smallest sovereign unit. A user has:

- An identity, owned by the Users module
- A set of authentication credentials, owned by the active auth adapter (the Users module ships the reference adapter)
- A set of membership rows linking them to Customers, Workspaces, and individual Modules

A user is **not** "a customer's employee." A user is a person. The same person can be an employee at one Customer, a contractor at another, and an operator across both. The framework models this as three membership rows, not three users.

### Why this matters

Tightly-coupled SaaS platforms typically model users by duplicating them — one user record per tenant. The moment a person moves between tenants, their identity, preferences, audit history, and personal data fork. Sovereign Portal refuses this. One person = one user.

### Users owns identity end-to-end

The Users module is the identity foundation. It owns the post-authentication surfaces (account self-service, admin user management) **and** the pre-authentication surfaces (signup, login, password reset, invitation acceptance) plus the short-lived token table that backs them. No separate "auth" or "registration" module — that boundary always leaked. The portal shell delegates every identity concern to Users.

---

## Scope Tier 2 — Customers (`companies`)

The Customer tier is the **governance boundary**. Almost every business decision a buyer cares about — "who can spend money," "who can change pricing," "who can invite new users" — lives here.

A Customer has:

- A canonical ID (`companyId`)
- An Owner (exactly one, transferable, audit-logged)
- A set of users (linked via `user_company_memberships`)
- A set of Workspaces (zero or more)
- A set of installed Modules (each with its own catalog of module-tier roles)
- A role catalog at the Customer tier (Owner, Admin, Member, Viewer by default — fully editable)

### The naming split

The service name is `companies`. The UI label is "Customers" by default. This is a deliberate split:

- **Canonical name** stays portable. If you are a marketplace platform, your "customer" is actually a seller. If you are an EHR vendor, your "customer" is actually a clinic. Re-labeling for your buyer's vocabulary is a one-line config change. Re-naming the service after deployment is a migration.
- **UI label** matches your buyer's language. The framework ships "Customers" because it is the most common case. You change it without touching anything else.

### Customer-tier governance, not Workspace-tier

We tried both during design. Customer-tier governance won because the buyer's accountant, lawyer, and compliance team all think at the Customer level, not the Workspace level. Billing, contracts, data residency, and audit reports all map cleanly to Customer. Workspaces are operational; Customers are accountable.

### Customers does not own users

Users are not attached to a Customer at company-creation time. Membership flows through `user_company_memberships`, managed by the Users module. The Customers module owns the company record and its operational metadata — phone, email, address, status, attached Locations, attached Pricing Sets. It does not own the user-membership graph. This separation matters: a code path that lets you "create a Customer and attach users" inevitably duplicates Users-module logic and drifts.

---

## Scope Tier 3 — Workspaces

The Workspace is the **operational unit**. Day-to-day work happens here. A Workspace has:

- A canonical ID (`workspaceId`)
- A parent Customer (`companyId`, denormalized on memberships for fast scope enforcement)
- An Owner (exactly one, transferable, audit-logged)
- A set of users (linked via `user_workspace_memberships`, scoped to this workspace)
- A role catalog at the Workspace tier (Owner, Manager, Member, Viewer by default)

### Workspaces are name-only

Workspaces have no type classification. Like a Slack workspace, a Workspace is defined by its name and its membership. Operational categorization (distribution, hub, retail, regional office) can live in the name itself — "Chicago Distribution," "West Coast Hub" — but it is not a structured field and it does not participate in permission logic or filtering. We removed the `workspace_type` field after watching it grow ad-hoc enum values that no consumer actually needed.

### The intentional absence of "Admin" at Workspace tier

The default Workspace catalog has no Admin role. Governance lives at the Customer tier — administering users, editing roles, managing billing. Workspaces handle **operations** — running orders, scheduling tasks, executing the work. Manager is the highest non-owner Workspace role.

This is enforced softly (you can add an Admin role to a Workspace catalog if your deployment needs one) but the default tells you the shape we expect.

### Modules install **into** Workspaces

When a buyer installs the Orders module, it gets installed into a specific Workspace. The Customer doesn't have a global Orders module — Workspace A might have Orders + Billing; Workspace B might have Orders + Inventory + Shipping. Each install is independent.

This is the configuration-not-code principle made concrete. Two Workspaces in the same Customer running different module sets are the **normal case**, not an edge case.

### The three-tier scope cascade

Workspaces sit in the middle of a three-tier *attachment* scope for cascading records like Pricing Sets and Locations:

| Attachment scope | Where it applies |
|---|---|
| Company-wide | Inherited by all Workspaces and all Locations within the company |
| Workspace | Inherited by all Locations within the Workspace |
| Location-specific | Applied to a single Location record only |

This is distinct from the four-tier scope hierarchy above — that one is about *who can see what*. This one is about *which record applies where*. Standard rates configured Company-wide; regional overrides at the Workspace tier; one-off adjustments at the Location tier.

### Cascade deactivation

A Workspace cannot be deactivated until all of its associated Locations, Orders, and Pricing Sets have been deactivated first. The UI enforces this with a blocking modal that lists every active record preventing deactivation. This prevents orphaned operational records and ensures nothing goes dark unexpectedly.

---

## Scope Tier 4 — Module records

A module is a sovereign service. It has:

- Its own backend service (its own process, its own port)
- Its own frontend service (mounted into the portal shell at a known route prefix)
- Its own data model (with sovereign storage — no other module can read it)
- Its own API surface (declared functions, accessed by peers through the peer registry only)
- Its own lifecycle (`onInstall`, `onUpgrade`, `onWorkspaceCreated`, `onUninstall`, `health`)
- Its own role catalog at the Module tier (Owner, Manager, Member, Viewer by default — overridable per module)
- A single registry export (`src/moduleRegistry.js`) that declares all of the above

### Modules are not framework primitives

This is the dogfood test. **Users, Customers, and Workspaces are themselves sovereign modules.** Same registry shape, same lifecycle hooks, same data ownership rules. The framework does not have a special "system table" for users that bypasses the SMI. Users live in the Users module. Customers live in the Customers module. Workspaces live in the Workspaces module.

If the framework cannot describe its own foundational modules through the SMI, the SMI is wrong. So the SMI describes them, and they pass conformance, and that's how we know the SMI works.

### Extensible record types

A module can declare its records as **typed extensions** of a base table, so new types are added without modifying the module's core schema. The reference Users module uses this pattern: every user has a `user_type` field (default `standard`), and types like `driver` or `sub_contractor` add a side table keyed by `user_id` carrying type-specific data (license number, vehicle info). New types are added by (1) defining a new type value, (2) creating an extension table, (3) surfacing the type in any UI filter that needs it. The base module spec does not change.

This is the recommended pattern for any module that needs to support a polymorphic record kind without forking.

---

## How permission decisions compose

Every request to a module goes through the three permission layers, in order. Each layer reads from one or more of the scope tiers above.

### Step 0 — Identity resolution

Before any layer runs, the auth adapter resolves the request into an `IdentityContext`. The context carries the user, the active Customer, the active Workspace, the active role assignments at each scope tier, and optionally an `operator: true` flag.

If resolution fails: `401`. No module ever sees the request. (Identity resolution is itself owned by the Users module — see "Users owns identity end-to-end" above.)

### Layer 1 — Module access gate

Does this user have the right to use this module at all, in this Workspace, on behalf of this Customer? The framework checks three things:

1. The user has a Customer role with at least `read` capability in the Customer.
2. The user has a Workspace role with at least `read` capability in the Workspace.
3. The user has a Module role record for the `(workspaceId, moduleName)` pair.

Absence of any → `403`, `reason: "layer1_denied"`. The module never sees the request.

### Layer 2 — Module-level role

If Layer 1 passed, what role does the user hold? The framework computes the user's **effective role** at each relevant scope tier (Customer + Workspace + Module) using the "highest rank wins" rule, and resolves the role record(s) that will govern the rest of the request.

This layer answers "who are they, in this context?" — not yet "what can they do?"

### Layer 3 — Granular permission

Can the user call this specific function on this specific record? The framework takes the union of capabilities from the effective roles computed at Layer 2 and checks against the function's declared `requiredCapabilities`.

Functions without declared requirements default to `read`.

For functions that return lists or queryable data, the framework also asks the module's `dataScope` policy what subset of records this caller can see. The policy returns a framework-neutral `ScopeFilter` (e.g. `{ kind: 'workspace', workspaceId: 'ws_123' }`), and the storage adapter translates that into the underlying query fragment. This is part of Layer 3 — it is the data-row variant of "does this role grant this action on this record."

### Why split it this way

Real-world permission errors come from blending these decisions into one. "User can access Orders, can call `listOrders`, but only sees orders in their workspace" is three distinct decisions, and conflating them is the single most common source of multi-tenant data leaks. The three-layer split is a structural defense. Every layer is independently testable; every layer has its own failure mode.

---

## Roles, capabilities, and "highest rank wins"

A role catalog is a versioned, editable list of role records scoped to one of the three governing scope tiers (Customer / Workspace / Module). Membership rows reference role records by `roleId`, never by name.

### Capability vocabulary (v0.2)

A small, closed set. Capabilities are **coarse** — they describe what a role broadly can do at the tier it applies to. Per-function flags are computed at Layer 3 from these capabilities.

| Capability | Meaning |
|---|---|
| `read` | View records in scope |
| `write` | Create and edit records in scope |
| `manage_users` | Add and remove users from the scope |
| `manage_settings` | Edit non-role settings in scope |
| `manage_roles` | Edit the role catalog for this scope |
| `transfer_ownership` | Move the Owner role to another user |
| `delete` | Delete the scope itself |

### Effective role computation

A user may hold multiple roles in the same scope (e.g. invited twice under different roles, or auto-assigned and then manually upgraded). When evaluating capabilities, the framework computes the **effective role** as the one with the highest `rank` value. Ties break by earliest `assignedAt`.

This is deterministic, audit-stable, and easy to explain to a buyer's CISO.

### Owner is special

Every scope (Customer, Workspace, Module instance) has exactly one Owner. Owners hold every capability. Ownership is transferable, always audit-logged, and the framework refuses to leave a scope without exactly one Owner — transferring is a swap, not a delete-then-add.

---

## Operators — the observability flag, not a tier or a layer

Operators are the staff who run the platform — your engineers, your support team, your incident responders, the consultancy that built the platform for you. They need a way to act inside customer environments to support them.

An operator is a User with `is_operator: true` on their identity. That flag does three specific things and only three things:

1. **Tenant switcher** — operators see a top-level "Operator view (all tenants)" entry plus every Customer they hold an actual membership row in. Non-operators see only the Customers they hold membership rows in.
2. **Audit log enrichment** — every write performed under an operator session is audit-logged with `operator_reason` (one of `support`, `incident`, `audit`, `migration`, `impersonation`).
3. **"Operator" badge** — surfaced in module Registries so customer admins can see at a glance which users in their scope are platform staff.

Crucially, the `is_operator` flag:

- Does NOT auto-grant any role in any scope.
- Does NOT bypass Layer 1, Layer 2, or Layer 3.
- Does NOT confer capabilities.

When an operator needs to act inside a Customer, they get a membership row in that Customer just like any other user. Their role assignment governs what they can do. The operator flag only governs whether the option to switch into that Customer is offered at all, and whether their actions get the audit-log enrichment.

This is the architecture that makes "we have access to support you" credible to a buyer's compliance team. The platform's own staff cannot silently act inside a tenant. Every operator action is a normal permission decision, traceable through the audit log, with a stated reason.

---

## The configuration-not-code outcome

This whole model exists to enable one thing: **adding a new customer, a new workspace, a new module instance, or a new role is configuration, not code.**

- New Customer? Create a row, run the install hooks, the framework wires it. The first user of a Customer auto-becomes its Owner via the self-serve onboarding flow owned by the Users module.
- New Workspace under that Customer? Create a row, the framework cascades the right defaults.
- New Module instance in that Workspace? Run `module.onInstall`, the framework imports the module's role catalog, the installing user becomes the Module Owner.
- New role that none of the defaults covered? Open Role Settings, add the role record, assign capabilities from the closed vocabulary, done.

Compare to the typical tightly-coupled SaaS shape: a new customer triggers a custom branch in user logic, a custom column in the billing table, a custom condition in the workspace query, a custom UI flag for the new role. Every "configuration" change is a code change. Every code change is a deploy. Every deploy is a risk. The cost of acquiring a new customer rises with every customer you have already acquired.

Sovereign Portal inverts that curve. The 100th customer costs the same to onboard as the 10th. The 1000th costs the same as the 100th.

---

## What this model deliberately does not have

- **No "team" tier between Workspace and User.** Teams are tag-like. If you need them, model them as a module — `Teams` becomes a sovereign module that any business module can compose against. We tried baking teams into the framework and the abstraction always leaked.
- **No "organization" tier above Customer.** If you need parent-of-customer (e.g. a holding company that owns five subsidiaries), the recommended pattern is to model it as a relationship at the application layer, not as a framework tier. The cost of adding a fifth tier to every membership table is too high relative to how often it is actually needed.
- **No "system" or "superuser" role that bypasses the model.** The closest thing is the operator flag, and even that does not bypass — it only enables choice and observability. Bypass roles always degenerate into the path that real attackers take.
- **No implicit role inheritance.** Customer Owner does not automatically make you Workspace Owner of every Workspace under the Customer. If you should own those Workspaces, you get explicit Owner role records. Implicit inheritance is unauditable.
- **No fourth permission layer.** Layer 3 covers granular per-function and per-record decisions. Earlier drafts called Modules a "fourth layer," but that conflated scope with check. The four-tier scope hierarchy is the *shape of the data*; the three-layer permission check is the *shape of the decision*. They are not the same axis.

---

## Source-of-truth pointers

- `docs/smi-spec.md` — the contract this model is enforced through
- `docs/module-registry-and-settings.md` — the Module Registry pattern that lets every module expose its own conformance to this model
- `docs/anti-patterns.md` — the mistakes we made while learning to enforce this model cleanly

---

*The shortest summary of this entire document is: **four-tier scope hierarchy (Users / Customers / Workspaces / Module records), three-layer permission check (module access / role / granular), one Owner per scope, configuration not code.** If you keep that in your head while reading the SMI spec, the spec will read as the obvious implementation. If you keep a tree-shaped multi-tenancy model in your head, parts of the SMI will look weird until you let the tree go.*
