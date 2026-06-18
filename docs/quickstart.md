# Quickstart — build your first sovereign module in 30 minutes

This walkthrough takes you from a fresh clone of Sovereign Portal to a running sovereign **Orders** module that lists, creates, and shows orders scoped to a Workspace, with a Module Registry and a Module Settings page, fully conformant to the Standard Module Interface (SMI).

The point of the walkthrough is not the Orders module specifically. The point is to see, in one sitting, what a sovereign module actually looks like — so when you build your own, the shape is already familiar.

**Prerequisites:** you have completed the README's 10-minute setup and have Sovereign Portal running at `http://localhost:3000`.

---

## Minute 0–5: Understand what you are about to build

A sovereign module has six parts. All six are required. Every module in Sovereign Portal — Users, Customers, Workspaces, and the Orders module you are about to build — has all six.

1. **A sovereign backend service** with its own data model (`orders-be`).
2. **A sovereign frontend service** mounted into the shell (`orders-fe`).
3. **A Module Registry** declaring the module's identity (module ID, service names, collections, routes, auth ownership, settings ownership).
4. **A Module Settings page** at `/dashboard/orders/settings` exposing Module Admins, Available Roles, Default Role, and the Module Registry.
5. **SMI conformance** — every request the backend handles carries UserID, CompanyID, Company Global Role, WorkspaceID, Workspace Global Role, and the module makes its permission decisions against those.
6. **A module document** following the 11-section template, captured in `docs/modules/orders.md`.

The `module-template` repo has placeholders for all six. You are going to copy it, rename it to Orders, and fill in the placeholders.

---

## Minute 5–10: Scaffold the module

```bash
cd /path/to/sovereign-portal
cp -r module-template/be orders-be
cp -r module-template/fe orders-fe

# Rename the package + service names
cd orders-be
sed -i '' 's/module-template/orders/g' package.json
sed -i '' 's/MODULE_TEMPLATE/ORDERS/g' src/config.ts
cd ../orders-fe
sed -i '' 's/module-template/orders/g' package.json next.config.mjs
cd ..

# Register the module with the shell
# Open portal-shell/next.config.mjs and add the rewrite block for /dashboard/orders/*
# (the template README in module-template/fe/README.md shows the exact lines)
```

You now have an `orders-be` and an `orders-fe` that compile, run, and serve the placeholder Orders pages — but with the orders identity baked in instead of the template identity.

---

## Minute 10–15: Define the data model

Open `orders-be/src/models/order.ts`. The template ships with a placeholder schema. Replace it with the minimum viable Orders schema:

```ts
import { Schema, model } from "mongoose";

const OrderSchema = new Schema({
  // SMI scope — every sovereign record is scoped to a Customer (Company) and Workspace
  companyId: { type: String, required: true, index: true },
  workspaceId: { type: String, required: true, index: true },

  // The thing the module actually owns
  orderNumber: { type: String, required: true },
  customerReference: { type: String },
  status: { type: String, enum: ["draft", "open", "closed"], default: "draft" },
  total: { type: Number, default: 0 },

  // Standard audit fields
  createdBy: { type: String, required: true },  // userId
  createdAt: { type: Date, default: Date.now },
  updatedAt: { type: Date, default: Date.now },
});

export const Order = model("Order", OrderSchema);
```

Notice what is NOT in this schema:

- No `userId` field other than `createdBy`. The module does not duplicate Users' data. When the FE wants to display the creator's name, it asks the Users module via the SMI.
- No `customerName` field. The module does not duplicate Customers' data. When the FE wants to display the Customer name, it asks the Customers module.
- No `workspaceName` field. Same reason.

**This is the discipline that makes the module sovereign.** Each module owns its slice of the schema and exactly its slice. Tight coupling happens when a module starts caching its neighbor's data "for convenience." Don't.

---

## Minute 15–22: Wire SMI conformance and the routes

Open `orders-be/src/routes/orders.ts`. The template includes the SMI middleware already — every request reaches your handler with `req.smi` populated. Replace the placeholder handlers with the Orders routes:

```ts
import { Router } from "express";
import { requireSMI } from "@sovereign-portal/smi";
import { Order } from "../models/order";

const router = Router();

// List orders in the current Workspace, scoped by SMI
router.get("/orders", requireSMI(), async (req, res) => {
  const { companyId, workspaceId } = req.smi;
  const orders = await Order.find({ companyId, workspaceId }).sort({ createdAt: -1 });
  res.json({ orders });
});

// Create a new order
router.post("/orders", requireSMI({ roles: ["orders.admin", "orders.member"] }), async (req, res) => {
  const { companyId, workspaceId, userId } = req.smi;
  const order = await Order.create({
    companyId,
    workspaceId,
    orderNumber: req.body.orderNumber,
    customerReference: req.body.customerReference,
    createdBy: userId,
  });
  res.status(201).json({ order });
});

// Get a single order — scoped, so a user from another Workspace gets a 404
router.get("/orders/:id", requireSMI(), async (req, res) => {
  const { companyId, workspaceId } = req.smi;
  const order = await Order.findOne({ _id: req.params.id, companyId, workspaceId });
  if (!order) return res.status(404).json({ error: "Not found" });
  res.json({ order });
});

export default router;
```

The SMI middleware does three things, in this order: it authenticates the request via the active session, it enriches the request with the user's Company and Workspace context for the current tenant, and it enforces any role requirements you declare. You did not write any of that. You just imported it.

---

## Minute 22–27: Wire the Module Registry and Settings

Open `orders-be/src/moduleRegistry.js`. The template ships the canonical registry shape — fill in Orders' values:

```js
// orders-be/src/moduleRegistry.js
module.exports = {
  key: "orders",
  label: "Orders",
  registryVersion: "v0.2",
  attachmentScopes: ["workspace"],
  dependencies: ["users", "workspaces"],
  smiPath: "/smi/orders",
  ownedCollections: ["orders"],
  events: {
    publishes: ["orders.created", "orders.fulfilled", "orders.cancelled"],
    subscribes: ["workspaces.deactivated"],
  },
  capabilities: [
    { key: "bulk_import", label: "Bulk import CSV", togglable: true, default: false },
  ],
  settingsSchema: {
    autoCloseAfterDays: { type: "number", default: 30, min: 1, max: 365 },
  },
  perRecordSettingsSchema: {},
  roles: {
    defaults: [
      { key: "orders.admin",  label: "Admin",  isDefault: false },
      { key: "orders.member", label: "Member", isDefault: true  },
      { key: "orders.viewer", label: "Viewer", isDefault: false },
    ],
  },
};
```

The FE reads this registry through `/smi/orders/registry` and renders the five standard Settings sections (Admins, Roles, Default, Capabilities, Registry) from it. The template's `orders-fe/src/pages/ModuleSettings.jsx` already does this — it pulls the registry once and maps it; you do not edit it per module.

```js
// MODULE_ADMINS is hardcoded for Phase A (FE-only).
// Phase B will fetch this from the backend's /v1/modules/orders/admins endpoint.
const MODULE_ADMINS = [
  // Bootstrap rule: first user of a tenant auto-becomes Module Admin
  // For Phase A, this is the first user in the Users module for this tenant.
];
```

Now open `orders-fe/app/page.tsx` and add a gear button in the page header that links to `/dashboard/orders/settings`. The template shows where.

---

## Minute 27–30: Smoke test

Restart the services:

```bash
docker-compose restart orders-be orders-fe portal-shell
```

Open `http://localhost:3000/dashboard/orders` — you should see an empty Orders list with the gear button in the header. Click the gear; you should land on the Module Settings page with the four sections rendering.

Create an order through the UI (the template's "New Order" button still works, pointed at the new backend). Refresh the list. Now open the Users module and invite a teammate by email; once they accept, they appear in your Workspace's user list and can see the Orders module too. You have a sovereign Orders module, a populated Workspace, and the end-to-end identity loop working.

---

## What you just learned

You built a module that:

- Owns its data and only its data. No duplication of Users, Customers, or Workspaces fields.
- Composes against the foundational tier through the SMI, not through ad-hoc database joins or shared tables.
- Publishes a Module Registry that any other module can discover.
- Exposes a Module Settings page consistent with every other module in the platform.
- Enforces role-based access via the SMI, not via custom middleware you wrote yourself.

This is the shape of every business module you will ever build on Sovereign Portal. Pricing has the same shape. Locations has the same shape. Billing has the same shape. The four-tier scope hierarchy, the three-layer permission check, and the SMI mean the boring 30% of every module — auth, scoping, roles, settings, registry — is already done. You spend your time on the interesting 70% — the actual business logic.

---

## Next steps

- Read `docs/smi-spec.md` for the formal Standard Module Interface contract.
- Read `docs/permission-model.md` ("Four-Tier Scope, Three-Layer Check") for why the architecture is shaped this way.
- Read `docs/module-registry-and-settings.md` for the full Module Registry + Settings specification, including the three-tier attachment scope (`company` / `workspace` / `location`).
- Read `docs/anti-patterns.md` for the mistakes we made so you do not have to.
- Read `docs/module-doc-template.md` for the 11-section structure every module document should follow.

When you are stuck, the documentation is the answer 90% of the time. When it is not, [Freshify](https://freshify.io) offers retainer support.

Welcome aboard.
