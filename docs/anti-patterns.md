# Anti-patterns

**The mistakes we made building Sovereign Portal, so you do not have to repeat them.**

---

This is the catalog of design decisions that looked reasonable, shipped, and then had to come out. Each entry is real — every one of these surfaced during the deploys that built the foundational tier. They are documented here because the cost of learning each lesson in production is high, and the catalog is portable in a way the bug fixes themselves are not.

If you are about to implement something and recognize it in this list, stop and read the alternative. If your intuition is fighting one of these warnings — "but in my case it's different" — you may be right, but read carefully first. The cases where these patterns seemed fine were exactly the cases where they shipped.

---

## §1 — Redirects inside an FE, when the shell mounts the FE under a prefix

### The mistake

You want a permanent redirect from a legacy route to the new one — say, `/dashboard/users/list/module-settings` → `/dashboard/users/settings`. You add it in the `users-fe` repo's `next.config.mjs` (or equivalent), push, smoke test, and watch the redirect land at the **shell root 404**.

### Why it breaks

The portal shell mounts each module's FE under `/dashboard/{module}/*` and **strips that prefix** before handing the request to the FE. So when the FE issues its redirect, the `Location` header points at a path the FE thinks is correct relative to its own root — but the browser interprets it relative to the shell, where the prefix is missing. Result: 404.

### The fix

**All cross-module redirects live at the shell layer.** The shell is the only layer that knows the fully-qualified `/dashboard/{module}` prefix. Define the redirect in `portal-shell/next.config.mjs` (or your shell's equivalent), verify with `curl -I` that you get a `308` with a fully-qualified `Location` header, and remove any stub redirects from the FE that initially looked like the right place.

### The warning sign

You're typing a redirect rule in a sub-FE that references a path containing another module's name, or any path starting with `/dashboard/`. That's a shell-layer concern, not an FE concern.

---

## §2 — The "operator can see everything" bypass

### The mistake

Early in the build it's tempting to give support staff a blanket cross-tenant bypass: "if `user.role === 'operator'`, return all companies and workspaces regardless of membership." It feels harmless. Operators are trusted.

### Why it breaks

It breaks the architecture you are selling. The moment any code path returns data without checking explicit membership, two things become true: (1) you cannot credibly tell a buyer's CISO "operators only see what they have explicit access to," and (2) the bypass becomes load-bearing — removing it later requires re-wiring every support workflow that grew to depend on it.

We shipped this bypass in early deploys (`listMyCompanies` and `listWorkspaces`). The cost of removing it later was a full sequenced migration: seed Module Admins first, then drop the bypass, then re-smoke every cross-tenant support workflow. If we had built Module Admins first, the bypass would never have shipped.

### The fix

**Module visibility is derived from membership.** Operators get access by being added as Module Admins (deployment-wide governance, see `docs/module-registry-and-settings.md` §3.2) or by being explicit members of the scope they need to access. The `operator: true` claim only opens the **option** to switch into a tenant; it does not auto-grant any role inside that tenant.

If you find yourself writing `if (user.isOperator) return everything`, you are about to ship the bypass. Stop. The Module Admin pattern is the correct shape.

### The warning sign

Any branch in a list endpoint that returns more data when a flag on the user is set. Even one. They compound.

---

## §3 — Hardcoded service names in business modules

### The mistake

The Orders module needs to call the Customers module. The path of least resistance is:

```ts
const url = `http://companies-be:8080/v1/companies/${companyId}`;
const res = await fetch(url);
```

Direct, fast, works.

### Why it breaks

You have just hardcoded `companies-be` (the service name) and `8080` (the port) and the route shape (`/v1/companies/:id`) into the Orders module. Three couplings, none of them declared in the descriptor, all of them invisible to the conformance suite. When the Customers module renames a route, splits in two, moves behind a gateway, or is mounted in a deployment that doesn't use `companies-be` as the service name, Orders breaks silently.

The whole point of sovereign modules is that the Orders module composes against a **contract**, not against an implementation. Hardcoding the implementation means you have a contract-shaped wrapper around a tightly-coupled codebase.

### The fix

```ts
const customers = ctx.peers.get<CustomersApi>("companies");
if (!customers) {
  throw new ModuleNotInstalledError("companies");
}
const result = await customers.functions.getCompany.handler({ companyId }, ctx);
```

The peer registry resolves the peer at runtime against whatever's actually installed. The Orders module declares `dependencies: ["companies"]` in its `src/moduleRegistry.js`, the peer registry refuses to resolve any other peer, and the conformance suite can statically verify that Orders never hardcodes a service URL.

### The warning sign

A string literal anywhere in business logic that matches the name of another module's backend service. If you grep your codebase for `companies-be` and find a hit in any module other than `companies`-`fe`, that's a violation.

---

## §4 — Cross-module data reads

### The mistake

The Orders module needs the user's display name when rendering an order. The Users module already has it in `users.displayName`. The "fast" implementation:

```ts
const user = await db.collection("users").findOne({ _id: order.createdBy });
order.creatorName = user.displayName;
```

You're not modifying users' data. You're just reading. What's the harm?

### Why it breaks

You have just established a hidden dependency on the Users module's schema. When Users renames `displayName` to `name`, Orders breaks. When Users adds a per-tenant access policy to that field, Orders bypasses it. When Users splits its data store, Orders cannot find the collection. The Users module has no way of knowing Orders is reading from it, so it cannot warn before changes, and the conformance suite cannot enforce sovereignty.

This is the **most expensive class of mistake to fix later** because the dependency is invisible. Refactoring it out requires finding every reader by grep across every module.

### The fix

Storage handles are scoped. The framework's `ModuleStorage` for Orders refuses to return a collection it does not own:

```ts
// This throws — Orders does not own the users collection
await ctx.storage.collection("users").findOne(...);
```

To get the user's display name, go through the Users module's declared API:

```ts
const users = ctx.peers.get<UsersApi>("users");
const user = await users?.functions.getUser.handler({ userId: order.createdBy }, ctx);
order.creatorName = user?.displayName;
```

If Users changes the field name, the API stays stable (or Users versions the API explicitly), and your code keeps working.

### The warning sign

You're about to write `db.collection(...)` in a module, and the collection name does not appear in the module's `moduleRegistry.ownedCollections`. Stop. The peer registry is the only legal path to a peer module's data.

---

## §5 — Reading auth headers from inside a module

### The mistake

A module needs to know whether the caller is signed in. The "obvious" implementation:

```ts
const token = req.headers["authorization"]?.replace("Bearer ", "");
const payload = jwt.verify(token, JWT_SECRET);
const userId = payload.sub;
```

### Why it breaks

You have just made the module depend on a specific identity provider, a specific token format, a specific signing key, and a specific header convention. The whole point of the pluggable auth adapter (SMI §8) is that you can swap Twilio OTP for Auth0 for Okta for Cognito without rewriting a single module. If modules read JWTs directly, that promise is a lie.

### The fix

The auth adapter is the **only** part of the framework that touches headers, cookies, JWTs, or external identity-provider SDKs. Modules receive a resolved `IdentityContext`. From inside a module:

```ts
const { userId, companyId, workspaceId, roles } = ctx.identity;
```

That's it. No JWTs. No headers. No knowledge of the auth provider.

### The warning sign

The string `Authorization`, `Bearer`, `jwt.verify`, `Cookie`, or `req.headers` appears in any file outside the auth adapter's own code. That's a leak.

---

## §6 — Module emits an event not declared in `publishes`

### The mistake

You add a new audit-style event mid-development: `orders.bulk_archived`. You emit it from inside the bulk archive handler. You forget to add it to the descriptor's `events.publishes` array because it's just an event, who's listening, who cares.

### Why it breaks

The framework type-checks every emit against the descriptor. Emitting an undeclared event throws at runtime. (This is intentional — undeclared events make event-driven systems unauditable; you can't render the topology from the descriptors if half the events aren't in them.)

But you don't discover this until production, because your local dev environment has framework debug mode on, which is lenient, and your CI doesn't exercise the bulk-archive path because nobody wrote a test for it yet.

### The fix

Declare every event you emit. The descriptor is the contract:

```ts
events: {
  publishes: [
    "orders.created",
    "orders.updated",
    "orders.archived",
    "orders.bulk_archived",  // ← add it here, then emit it
  ],
  subscribes: [],
},
```

Run the conformance suite locally before push. `sovereign-portal verify` catches undeclared emits statically (it walks the source for `ctx.emit({ name: "..." })` calls and checks every name is in `events.publishes`).

### The warning sign

You're about to emit an event whose name doesn't already appear in your descriptor. That's a two-line change before you write the emit. Do it first.

---

## §7 — Module Settings page is a Client Component

### The mistake

The Module Settings page (see `docs/module-registry-and-settings.md` §3) has four sections of data — Module Admins, Roles, Default Role, Registry. The instinct is to wire it as a Client Component with `useState` for editing, optimistic UI, and `fetch` calls to the BE.

### Why it breaks

Two ways. (1) In Phase A, the data is hardcoded — there is no BE to fetch from yet, and you're shipping client interactivity that does nothing. (2) In Phase B, when the BE lands, Server Components give you free auth integration (the session cookie is read on the server before the page renders) and zero client JS for the read path, which makes the page fast on cold loads and impossible to manipulate via DevTools.

Every Module Settings page in the foundational tier is a Server Component. Editing happens via Server Actions, not client fetches. The page works without JavaScript enabled.

### The fix

```tsx
// app/settings/page.tsx
export default async function SettingsPage() {
  const registry = await getModuleRegistry();          // server-only
  const admins = await getModuleAdmins();              // server-only
  const roles = await getRoleCatalog();                // server-only
  const defaultRole = roles.find(r => r.isDefault);
  return <SettingsView {...{ registry, admins, roles, defaultRole }} />;
}
```

Phase A: the three getter functions return hardcoded data. Phase B: they call the BE. The component layout doesn't change. Client interactivity (the "Edit Role" button, the "Add Module Admin" form) is opt-in per row, wrapped in small Client Components that submit Server Actions.

### The warning sign

The file declaring your Settings page has `"use client"` at the top. It shouldn't.

---

## §8 — Per-record settings labeled "Module Settings"

### The mistake

Early in the foundational tier, the per-record settings page (the one at `/dashboard/{module}/{id}/settings` — settings for one specific user, or one company, or one workspace) was labeled "Module Settings." This was correct in an earlier model where "module" meant "this user's module memberships."

Then we added the **actual** module-wide Settings page at `/dashboard/{module}/settings`. Now the label "Module Settings" was on the wrong page.

### Why it breaks

Operators looking for the module-wide settings page would click the gear next to a single record and land on per-record settings instead. They'd see a settings page for that one Workspace and wonder where the deployment-wide module settings lived. The label collision was the entire user-experience bug.

### The fix

Rename the per-record label to **"Settings"** (no "Module" qualifier). Keep the route intact (`/dashboard/{module}/{id}/settings`) so deep links still resolve. The module-wide page at `/dashboard/{module}/settings` keeps the full "Module Settings" naming in headers and breadcrumbs because at that level it's unambiguous.

Better yet, in your initial design, **reserve "Module Settings" for the module-wide page from day one**. The pattern this catalog enforces:

| Route | Label |
|---|---|
| `/dashboard/{module}/settings` | Module Settings (deployment-wide) |
| `/dashboard/{module}/{id}/settings` | Settings (per-record, scoped to that record) |

### The warning sign

The same words ("Module Settings", "Admin", "Settings") used on two different pages with different scopes. Pick distinct labels per scope.

---

## §9 — In-FE redirect for a route the shell handles

### The mistake

You ship a redirect inside the module FE and the shell layer at the same time, "to be safe." The FE redirect was supposed to be defensive — what if someone hits the FE directly?

### Why it breaks

The two redirects can disagree. One ships first (FE goes out in a deploy), then the second (shell) updates. For a window of time, hitting the legacy URL bounces through the FE redirect (broken Location header per §1), and the shell redirect never gets a chance to fire because the FE redirect responded first.

We hit this exact case in `users-fe` during the registry+settings rollout. Initial commit added an FE-layer redirect. Two commits later we removed it because the shell-layer redirect (added in the same deploy) was the one that worked.

### The fix

**One redirect, at the right layer.** Cross-module / cross-prefix redirects belong at the shell. Within-FE redirects (e.g. `/dashboard/users/old-tab` → `/dashboard/users/new-tab` where both paths stay inside `users-fe`) belong in the FE. Never both for the same source URL.

### The warning sign

You're about to add a defensive redirect "in case someone hits the FE directly." Resist. If someone hits the FE directly, the FE's normal routing handles it. Belt-and-suspenders redirects collide.

---

## §10 — Returning more data than the caller can use

### The mistake

The list endpoint for invites returns 20 fields per row, because future UI might need them. The detail endpoint returns 35 fields. Why filter on the server when the client can just ignore fields it doesn't render?

### Why it breaks

Two ways. (1) The data-access policy (SMI §2, third decision) has to filter every field individually. If the list endpoint returns invitee email, invitee phone, internal notes, and operator reason, the policy has to decide which of those four fields each role can see. Sending all of them and filtering on the client is a data leak waiting for someone to read the response in DevTools. (2) Every additional field is a coupling — if the FE ever ends up depending on `internalNotes`, you can't remove it without breaking the FE, even though it shouldn't have been there in the first place.

### The fix

**Endpoints return the minimum viable shape.** The list endpoint returns what the list view needs. The detail endpoint returns what the detail view needs. Add fields when the UI grows; do not pre-emptively widen the response.

For the foundational tier, the invites list went from 20 fields to 8 between Deploy 5.8 and 5.12 — the wider shape was a Deploy 5.8 mistake corrected as soon as we noticed list rendering was loading email-delivery error tooltips that operators didn't need.

### The warning sign

A list endpoint that returns more than 10 fields per row, or a list endpoint shape that exactly equals the detail endpoint shape. Lists should be narrower than details, structurally.

---

## §11 — `?next=evil.com` open redirect

### The mistake

The login page accepts a `next` query parameter so users land on the page they were trying to reach before being asked to sign in. The naive implementation:

```ts
const next = searchParams.next ?? "/dashboard";
return redirect(next);
```

### Why it breaks

An attacker sends a victim `https://your-portal.com/login?next=https://evil.com/fake-portal`. After the victim signs in (legitimately, on your domain), they get redirected to `evil.com`, which has been set up to look like your portal and harvests further credentials. The legitimate sign-in is the entire phishing payload.

### The fix

**Same-origin-clamp every `next` value on the server side** before passing it to a redirect. The pattern that shipped in the foundational tier:

```ts
function safeNext(raw: string | undefined, fallback = "/dashboard"): string {
  if (!raw) return fallback;
  if (!raw.startsWith("/")) return fallback;     // must be a path
  if (raw.startsWith("//")) return fallback;     // not a protocol-relative URL
  // additional rules: must not contain ".." sequences, must be < 2048 chars, etc.
  return raw;
}

return redirect(safeNext(searchParams.next));
```

Same clamp on the logout endpoint. Same clamp anywhere `next` flows through into a `redirect()` call.

### The warning sign

A `redirect()` call anywhere in the codebase whose target comes from query params, form fields, or headers. Every one of those needs the clamp.

---

## §12 — Cookie-using endpoints behind `0.0.0.0:8080`-derived URLs

### The mistake

A Server Component reads the session cookie, decides the user isn't signed in, and redirects to `/login?next=<current-url>`. The "current URL" is constructed from `headers().get("host")` — which on Cloud Run returns `0.0.0.0:8080`, the container's internal listen address.

### Why it breaks

The redirect lands the user at `https://0.0.0.0:8080/login?next=...`, which the browser cannot resolve. Sign-in is broken for every anonymous request.

### The fix

Build absolute URLs from the **`x-forwarded-host`** and **`x-forwarded-proto`** headers that Cloud Run (and every other reverse-proxied environment) sets:

```ts
const proto = headers().get("x-forwarded-proto") ?? "https";
const host = headers().get("x-forwarded-host") ?? headers().get("host");
const absoluteUrl = `${proto}://${host}${path}`;
```

The same pattern applies to anywhere you construct an absolute URL on the server: invite emails, password-reset links, OAuth callbacks. Always prefer `x-forwarded-*` over `host` in containerized environments.

### The warning sign

Any line constructing an absolute URL from `headers().get("host")` directly. Add the `x-forwarded` fallback.

---

## §13 — Optimistic UI that contradicts server state

### The mistake

A user clicks "Resend Invite." The FE optimistically updates the row to "Sent just now" before the server responds, because that's a good UX pattern.

### Why it breaks

The server returns 410 ("invite was revoked while you were looking at it"). The FE has already painted "Sent just now." The user's mental model is now out of sync with the data. They tell support "I resent it but it didn't go." Support checks the invite, sees it's revoked, escalates. Time wasted, trust eroded.

### The fix

For state transitions that the server might reject (most of them), don't paint until the server confirms. For instantaneous reads, optimistic UI is fine. For mutations with non-trivial server-side validation, wait. The latency cost is usually 100–200ms — small enough that the UX feels responsive without the lying.

If you want the responsiveness, show a spinner on the button, disable it, and update the row only after the response lands. That's still <300ms total and the user sees a clear "thinking" state.

### The warning sign

`setState({ status: "sent" })` immediately followed by a `fetch()` whose response could plausibly be an error.

---

## §14 — Generic role names

### The mistake

The module declares roles called `admin`, `member`, `viewer`. The Customer catalog declares roles called `admin`, `member`, `viewer`. The Workspace catalog declares roles called `admin`, `member`, `viewer`. They have nothing in common except the names, and the framework refuses to compare them across layers (SMI §1, "roles are namespaced by layer").

### Why it breaks

When a user holds three different "admin" roles — one at Customer, one at Workspace, one at Module — every conversation about their permissions has to start with "which admin?" Membership rows in the database all look identical. Bugs that mix up layers are nearly invisible during code review.

### The fix

**Namespace every role.** The convention that shipped:

| Layer | Role key examples |
|---|---|
| Customer | `company.owner`, `company.admin`, `company.member`, `company.viewer` |
| Workspace | `workspace.owner`, `workspace.manager`, `workspace.member`, `workspace.viewer` |
| Module (Orders) | `orders.owner`, `orders.manager`, `orders.member`, `orders.viewer` |

Now grep `orders.admin` and you find every reference to Orders-tier admin, with zero false positives. Audit-log entries are self-describing. Migration scripts can be confident about which layer they're touching.

The role `label` (display name) can still be plain "Admin" or "Owner" in the UI — that's a presentation choice. The `key` (machine name) carries the namespace.

### The warning sign

Two `roleId` values across different catalogs that have the same `key`. The framework allows it (catalogs are independent) but it's a recipe for confusion. Pick distinct keys.

---

## §15 — Graceful-skip without an audit trail

### The mistake

The invite-send code path tries to send the email, sees the COMMS_SHARED_SECRET isn't configured yet, and gracefully skips:

```ts
if (!secret) {
  console.warn("comms_secret_not_configured");
  return; // skip silently
}
```

This is "graceful" because it doesn't crash. The invite is still minted, the row still exists, the audit log just... doesn't have the failure.

### Why it breaks

The whole point of an audit trail is that it captures every attempt, succeeded or not. A graceful-skip without an audit entry means an operator looking at the invite a week later sees no email-send attempt at all — they assume one was never made and try to resend, or worse, assume the email went out and chase the invitee for not responding.

We shipped this exact bug in Deploy 5.8. The first patch (`15e153b`) added the audit-event emit to the graceful-skip path so every send attempt — whether it succeeded, failed at the transport, or skipped because configuration wasn't ready — leaves a row in the audit log.

### The fix

```ts
if (!secret) {
  await emitAudit("portal.invite_email_failed", {
    inviteId,
    error: "comms_secret_not_configured",
    trigger: "initial",
  });
  return;
}
```

The principle: **every state transition is audited, every attempt is logged, even the ones that gracefully skipped.** Failures without audit are invisible; invisible failures are unfixable.

### The warning sign

`return early` from an error path without a corresponding audit emit on the way out. The graceful skip is fine; the silent graceful skip is not.

---

## §16 — Mixing semantic-color tokens into module UIs

### The mistake

The portal shell uses a violet accent. A module UI imports React Aria components that come pre-styled with green for success states and red for errors. You ship the page; the brand discipline cracks.

### Why it breaks

Sovereign Portal's reference theme is intentionally restricted — violet + grey + white for branded deployments, black/white/grey only for the public reference. Red/green/yellow/amber are off the palette by design. The moment one module brings them in, every other module looks broken by comparison, and "Sovereign Portal looks intentional" becomes "Sovereign Portal looks half-themed."

Beyond brand, semantic colors don't survive theming. A buyer who wants their deployment in their corporate orange/teal can't easily override green-means-success across modules that bake it in. The framework solved this with **neutral surfaces** (`var(--surface-2)`, `var(--line-strong)`, `var(--fg)`) and accent variables.

### The fix

Use the framework's surface and accent variables:

- Success / info / warning / error states: use `var(--surface-2)`, `var(--line-strong)`, `var(--fg)` for the panel; lean on **iconography and copy** (checkmark + "Verified") rather than color
- Interactive accent: `var(--violet)` for the branded reference, or whatever single accent the deployment has selected
- Hover, pressed, focus: use `var(--violet-soft)` tints rather than separate hue families

Module FE code never imports a UI library that ships its own theme. The framework provides the design tokens; modules consume them.

### The warning sign

Hex values for red, green, yellow, or orange appearing in any module's CSS. Or a UI library imported with its default theme intact. Either is a brand-discipline regression.

---

## §17 — Treating Users / Customers / Workspaces as framework primitives

### The mistake

You're building a new module. You need to look up a user. You think, "Users is part of the framework — I'll call it differently from how I'd call any other module." Maybe you reach into the `users` collection directly because "auth is framework, not a module." Maybe you `require()` a file from inside the `users-be` repo. Maybe you copy the User shape into your own module so you can typecheck without a peer call.

### Why it breaks

It violates the dogfood test. **Users, Customers, and Workspaces are sovereign modules with the same registry shape as Orders, Pricing, or anything you build.** The framework eats its own dogfood by treating them this way. If you give them special treatment in your code, you've now coupled your module to a privileged framework primitive that doesn't actually exist — and your module will fail conformance the moment someone runs the suite.

For the same reason: there is **no `@sovereign-portal/core` package** to import shared types or shared functions from. Earlier drafts of this framework referred to one; it does not exist and never shipped. Every module is a stand-alone repo. Every cross-module contact goes through the peer registry.

This matters most when the framework itself evolves. When the Users module gains a feature (say, role catalog versioning in v0.2), every other module gets that feature through the same peer-registry call. If you bypassed the peer registry, you skip the upgrade.

### The fix

```js
// Wrong:
const user = await db.collection("users").findOne({ _id: userId });
// or, equally wrong:
const { User } = require("../../users-be/src/models/User");

// Right:
const usersRegistry = await peers.get("users");
const user = await peers.call("users", "getUser", { userId });
```

The Users module is just another peer. The peer registry doesn't care that it ships in the box. Conformance doesn't care. Treat it identically to a third-party module a buyer might write.

### The warning sign

Any module-internal `require()` or `import` that resolves into a foundational module's source code instead of through the peer registry. Any string literal `"@sovereign-portal/core"` anywhere in the codebase. Either is a violation.

---

## §18 — Reaching into another module's sub-feature data

### The mistake

Your Orders module wants to know whether a user has any pending invites before showing them the "Add teammate" CTA. Instead of asking the Users module through the peer registry, you write:

```ts
// Wrong:
const pending = await db.collection("invites").countDocuments({ userId, status: "pending" });
```

It works. The collection is there. The query is fast. Everyone moves on.

### Why it breaks

You have just made the Users module's invite feature undeletable for this deployment. The whole point of sub-feature sovereignty is that a deployment can turn off invites without breaking Orders. The README's "Turning things off" patterns and the SMI §7 schema-ownership rule both assume **nobody else reads the `invites` collection**. By reaching into it, you have silently broken the property the framework was built to give you.

Worse: the conformance suite catches it (§7 schema-ownership static check). So this code never should have shipped — someone disabled the suite or never ran it.

### The fix

Go through the peer registry. Add `pendingInvitesForUser` to the Users module's declared API if it isn't there yet (it should be — anything another module legitimately needs is API surface, not raw data):

```ts
// Right:
const users = ctx.peers.get<UsersApi>("users");
const pending = await users?.functions.pendingInvitesForUser.handler({ userId }, ctx);
```

Now if the deployment turns invites off, `pendingInvitesForUser` returns `0` (or the peer call returns undefined), and Orders' CTA logic short-circuits cleanly. No coupling, no broken feature.

### The warning sign

Any `storage.collection(...)` or `db.collection(...)` or direct ORM query against a collection name your module doesn't own. The exact symptom is `collection("<not-mine>")` — grep for collection names from other modules in your codebase. Any hit is this anti-pattern.

---

## §19 — Agents owning their own collections

### The mistake

You're building the Customer Support module's AI agent. The agent needs to track which tickets it has drafted replies for, so the operator UI can show "Agent drafted a reply 2 minutes ago." The "obvious" implementation:

```js
// support-agent/src/db/draftHistory.js
await db.collection("agent_draft_history").insertOne({ ticketId, draftedAt });
```

The agent has a MongoDB connection. It's a Node service. Of course it can own a collection.

### Why it breaks

Agents are **sidecars** — bonded to one parent module, with no registry entry of their own, no schema, and no entries in `ownedCollections`. The moment an agent owns a collection, it has become a hidden second module in the system: it must be deployed independently, migrated independently, monitored independently, and reasoned about independently. The parent module's source of truth no longer captures its full state.

Worse: any other module that needs the agent's data has no legitimate path to read it. The peer registry only resolves real modules. The agent has now created the exact tight coupling sovereignty exists to prevent.

### The fix

The agent writes through the parent module's `/agent/*` hooks. The parent module owns the data — if the operator UI needs to show "agent drafted a reply," then "agent drafted" is a state on the ticket, and the agent calls `POST /agent/tickets/{id}/draft` to record it. The parent decides what's allowed and audits the write.

```js
// support-agent/src/patterns/advisory.js
await parentClient.post(`/agent/tickets/${ticketId}/draft`, { body: draft });
```

### The warning sign

A `db.collection(...)` or `mongoose.model(...)` call inside an agent repo. Any `ownedCollections` field declared inside an `agent` directory. Either is a violation.

---

## §20 — Platform-wide agents that span modules

### The mistake

You've built useful agent logic for the Customer Support module — it classifies incoming tickets, drafts replies, escalates. The team asks: "Could the same agent also classify incoming Orders, and incoming Pricing inquiries, and incoming Locations alerts?"

The "efficient" answer is to generalize: one agent service that accepts events from every module, dispatches against a routing table, and writes back to each module's `/agent/*` hooks.

### Why it breaks

A platform-wide agent has become its own module — with its own deployment lifecycle, its own state, its own opinions about every other module's domain, and no `key` in the registry. It violates sovereignty in both directions: every other module now hard-depends on it for any agent-mediated behavior, and it has effectively become the framework's twelfth foundational module without going through any of the registry, conformance, or governance contracts.

Further: the agent's prompt now has to encode the domain knowledge of every module it serves. That prompt becomes a giant grab-bag that nobody owns, no parent module's specification covers, and every module's evolution can silently break.

### The fix

One agent per parent module. The Customer Support agent serves Customer Support. If Orders needs an agent, Orders ships its own agent sidecar with its own prompt, its own LLM provider choice, its own capability toggles in the Orders registry. Share underlying utilities (LLM adapter, retry logic, service-principal auth) by copy-paste across agent repos — not by a shared deployed service.

This is the same discipline the framework applies to modules. A shared business-logic service that spans modules is an anti-pattern at the BE tier; it is also an anti-pattern at the agent tier.

### The warning sign

An agent repo whose configuration accepts a list of parent module keys instead of exactly one. An agent's `parentClient` that holds more than one base URL. Either is a violation.

---

## How to use this catalog

This document is meant to be **grep-able** as much as read end-to-end. Search for the symptom (`0.0.0.0`, `Authorization`, `useState`, `companies-be` as a string literal, `@sovereign-portal/core`) and you should land on the anti-pattern that warns about it.

When you discover a new anti-pattern in your deployment that this catalog doesn't cover, add it. Pull requests against `docs/anti-patterns.md` are graded against one bar: **is this a mistake that someone building a sovereign module is reasonably likely to make, and is the fix non-obvious before you've made it once?** Yes → add it. No → it's just a coding tip, not an anti-pattern.

This catalog is the most expensive thing in the repo to write because the lessons cost real deploy time. It's also the most valuable thing in the repo to read, because reading it costs an afternoon and saves the same deploys.

---

## Source-of-truth pointers

- `docs/smi-spec.md` — the contract these anti-patterns describe violations of
- `docs/permission-model.md` — the conceptual model the framework enforces (Four-Tier Scope, Three-Layer Check)
- `docs/module-registry-and-settings.md` — the registry + settings pattern most of these anti-patterns relate to
- `module-template/` — the reference scaffold that demonstrates the right shape for every contract these anti-patterns violate

---

*If you read this catalog before you start building and you still hit one of these anti-patterns, that's fine — you'll recognize it faster and the fix will be cheaper. The goal isn't perfection on the first try. The goal is that none of these mistakes survive into a release.*
