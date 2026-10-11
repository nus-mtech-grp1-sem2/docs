# OneStage — System Design

*SWE5001 — Architecting Scalable Systems, Graduate Certificate in Architecting Scalable Systems (NUS–ISS)*

Data models, domain class diagrams, and API surface for the six backend services, derived from the [user stories](https://claude.ai/code/artifact/7a3e1db9-56dc-4d3f-8bc1-3c5d870a97a2). One Amazon RDS for MySQL instance plays five independent databases via schema-per-service; Cognito owns user authentication and credentials; the stateless Authentication Service validates the browser-to-backend identity flow; the Authorization Policy Engine owns application authorization; and a single SQS queue carries the one hand-off that can safely be asynchronous.

**At a glance:** 6 backend services · 1 MySQL instance, 5 schemas · 13 tables · 36 OneStage API endpoints · 1 SQS queue.

---

## Architecture overview

Three static single-page apps (Buyer, Organizer Portal, Scanner) are served from S3 via CloudFront and call the backend over HTTPS with a Cognito JWT. Path-based routing on a single ALB/API Gateway sends each request to the right ECS service. Every service owns one schema in one shared MySQL instance — there is no cross-schema foreign key anywhere in this design, only plain columns that reference another schema's row by id, exactly as if each service had its own database.

```mermaid
graph TB
    subgraph Frontend["Static Frontend — S3 + CloudFront"]
        Buyer["Buyer App"]
        Portal["Organizer Portal"]
        Scanner["Scanner App"]
    end

    Cognito[("Amazon Cognito<br/>User Pool")]

    GW["ALB / API Gateway<br/>path-based routing"]

    subgraph ECS["Amazon ECS Cluster"]
        AS["Authentication<br/>Service"]
        EIS["Event & Inventory<br/>Service"]
        WR["Waiting Room /<br/>Queue Service"]
        CPS["Checkout & Payment<br/>Service"]
        TIV["Ticket Issuance &<br/>Validation Service"]
        APS["Authorization<br/>Policy Engine"]
    end

    subgraph DB["Single Amazon RDS for MySQL Instance"]
        SchemaEI[(event_inventory schema)]
        SchemaQ[(queue schema)]
        SchemaCO[(checkout schema)]
        SchemaTI[(ticketing schema)]
        SchemaAU[(authorization schema)]
    end

    SQS{{"Amazon SQS<br/>order-events queue"}}

    Buyer -->|HTTPS + JWT| GW
    Portal -->|HTTPS + JWT| GW
    Scanner -->|HTTPS + JWT| GW
    Buyer -.sign in.-> Cognito
    Portal -.sign in.-> Cognito
    Scanner -.sign in.-> Cognito

    GW --> EIS
    GW --> WR
    GW --> CPS
    GW --> TIV
    GW --> AS

    AS -.validate JWT via JWKS.-> Cognito

    EIS -->|authorize action| APS
    WR -->|authorize action| APS
    CPS -->|authorize action| APS
    TIV -->|authorize action| APS
    APS -.validate JWT via JWKS.-> Cognito

    EIS -->|owns| SchemaEI
    WR -->|owns| SchemaQ
    CPS -->|owns| SchemaCO
    TIV -->|owns| SchemaTI
    APS -->|owns| SchemaAU

    CPS -->|publishes OrderPaid| SQS
    SQS -->|consumed by| TIV
    CPS -.confirm hold, sync.-> EIS
    WR -.check availability, sync.-> EIS
```

---

## Design decisions

**One database, five schemas, no cross-schema foreign keys.** A single Amazon RDS for MySQL instance hosts `event_inventory`, `queue`, `checkout`, `ticketing`, and `authorization` — one per service — instead of five separate RDS instances, which keeps the school project's AWS bill and ops surface small. Each service's own tables carry real, enforced foreign keys. A reference to another service's row (e.g. `checkout.orders.event_id` or `authorization.event_role_assignments.event_id`) is stored as a plain unconstrained column instead, so the services stay logically independent and could be split onto separate instances later with zero schema change.

**Only one thing has to be synchronous: not overselling.** The one failure OneStage cannot tolerate is two buyers being confirmed for the same seat. So reserving and confirming an `InventoryHold` happens inside the Event & Inventory Service under a DB transaction, and Checkout calls `POST /holds/{id}/confirm` synchronously before it will mark an order `PAID` — if that call fails, the sale fails. Ticket generation and the confirmation email are not on that critical path, so Checkout instead publishes `OrderPaid` to the `order-events` SQS queue and Ticket Issuance consumes it asynchronously. That's the proposal's "event bus that decouples inventory and order events from downstream processing," scoped to the one hand-off where eventual consistency is actually fine.

**Authentication and authorization are separate concerns.** Cognito authenticates users and issues tokens. The Authorization Policy Engine maps the token's immutable `sub` claim to an application user, loads event-role facts from its own schema, and evaluates action-specific policy in version-controlled code. Organizer and Event Helper are per-event roles and therefore do not become Cognito groups. Every domain service remains responsible for enforcing the returned decision before performing the requested action.

**What's deliberately left out.** Network firewalls and WAF rules, a service mesh, and rate limiting beyond the waiting room's own admission control are out of scope. IDs below are plain auto-increment `BIGINT`s rather than UUIDs, and every domain-specific "email" field is a denormalized snapshot taken from the Cognito JWT at write time, so no service has to call another just to render a name.

---

## Authentication and authorization

Authentication answers *who is making the request*. Authorization answers *whether that user may perform this action on this resource*. Cognito is the identity provider, the stateless Authentication Service exposes the backend identity-verification boundary, the Authorization Policy Engine is the central policy decision point, and each domain service is a policy enforcement point. The Authentication Service owns no credential or password database because Cognito owns credentials, MFA, token issuance, and browser sessions.

### Authentication flow — Cognito Hosted UI with Authorization Code and PKCE

The browser never handles a client secret. It generates a PKCE verifier/challenge, redirects the user to Cognito Managed Login, receives a short-lived authorization code, and exchanges that code plus the verifier for tokens. The frontend sends the Cognito **access token**, not the ID token, as the API bearer token.

```mermaid
sequenceDiagram
    actor U as User
    participant SPA as OneStage SPA
    participant C as Cognito Managed Login
    participant API as OneStage API

    U->>SPA: Open /login
    SPA->>SPA: Generate PKCE verifier and challenge
    SPA->>C: /oauth2/authorize (code + challenge)
    C->>U: Authenticate user and complete MFA if required
    C-->>SPA: Redirect URI with authorization code
    SPA->>C: /oauth2/token (code + verifier)
    C-->>SPA: Access, ID and refresh tokens
    SPA->>API: API request + Bearer access token
```

The access token is validated for signature, issuer, expiry, app client, and `token_use=access`. The immutable Cognito `sub` claim is the external identity key. Email and username are not authorization identifiers because they can change.

### Cognito-managed authentication endpoints

These endpoints belong to Amazon Cognito, not to a OneStage backend service. The OAuth endpoints use the configured Hosted UI domain, while OIDC discovery and signing keys use the user-pool issuer domain. They are listed because the SPA and backend token validators depend on their contract. They are not included in the OneStage API endpoint total above.

| Method | Path | Cognito host | Purpose | Caller |
|---|---|---|---|---|
| GET | `/oauth2/authorize` | Hosted UI domain | Start Managed Login using Authorization Code and PKCE | SPA / browser |
| POST | `/oauth2/token` | Hosted UI domain | Exchange an authorization code or refresh token for tokens | SPA OAuth library |
| GET | `/logout` | Hosted UI domain | End the Cognito browser session and redirect to an allowed sign-out URL | SPA / browser |
| GET | `/.well-known/openid-configuration` | User-pool issuer domain | Discover issuer and OAuth/OIDC endpoint metadata | OAuth clients / tooling |
| GET | `/.well-known/jwks.json` | User-pool issuer domain | Retrieve public keys used to validate Cognito JWT signatures | Backend token verifier |

The app client is public and therefore has no client secret in the browser. Callback URLs, sign-out URLs, scopes, and Authorization Code grant support are configured on the Cognito app client.

### OneStage Authentication Service endpoints

| Method | Path | Description | Caller |
|---|---|---|---|
| GET | `/auth/me` | Validate the access token and return safe identity claims | Authenticated SPA / diagnostics |
| GET | `/auth/health` | Report liveness/readiness without exposing Cognito configuration or secrets | Platform / load balancer |
| POST | `/auth/roles/sync` | Transitional synchronization of the legacy Cognito Customer group | SPA during migration only |

`POST /auth/roles/sync` exists in the current implementation but is deprecated in the target architecture. It must not grant Organizer or Event Helper access, and it is removed after all authorization decisions use RDS-backed assignments. New event-role behavior must not depend on Cognito groups or claims populated by this endpoint.

### Authorization decision flow

The domain service passes the original Cognito access token and a semantic action/resource request to the Authorization Policy Engine. The frontend may hide unavailable controls for usability, but frontend state is never an authorization authority.

```mermaid
sequenceDiagram
    actor U as User
    participant SPA as OneStage SPA
    participant DS as Domain Service
    participant APS as Authorization Policy Engine
    participant C as Cognito JWKS
    participant ADB as authorization schema

    U->>SPA: Perform an event action
    SPA->>DS: Request + Bearer access token
    DS->>APS: POST /authorization/decisions + original token
    APS->>C: Resolve signing key when not cached
    APS->>APS: Validate token and extract Cognito sub
    APS->>ADB: Load user and active event-role assignments
    ADB-->>APS: Identity and role facts
    APS->>APS: Evaluate action policy
    APS-->>DS: allowed, reason, policyVersion
    alt allowed
        DS->>DS: Perform domain action
        DS-->>SPA: Success
    else denied
        DS-->>SPA: 403 Forbidden
    else decision unavailable
        DS-->>SPA: 503 Service Unavailable (fail closed)
    end
```

The policy engine returns a decision; it does not perform the business action. Unknown actions, invalid resource context, database failures, and indeterminate decisions never default to allow.

### Authorization data model — `authorization` schema

```mermaid
erDiagram
    USERS ||--o{ EVENT_ROLE_ASSIGNMENTS : receives
    USERS ||--o{ EVENT_ROLE_ASSIGNMENTS : grants

    USERS {
        bigint user_id PK
        varchar cognito_sub UK "immutable Cognito subject"
        varchar email "profile snapshot, not an auth key"
        enum status "ACTIVE, SUSPENDED, DELETED"
        datetime created_at
        datetime updated_at
    }
    EVENT_ROLE_ASSIGNMENTS {
        bigint assignment_id PK
        bigint user_id FK
        bigint event_id "logical ref -> event_inventory.events, no FK"
        enum role "ORGANIZER, EVENT_HELPER"
        enum status "ACTIVE, REVOKED"
        datetime valid_from "nullable"
        datetime valid_until "nullable"
        datetime revoked_at "nullable"
        bigint assigned_by_user_id FK "nullable for system bootstrap"
        datetime created_at
        datetime updated_at
    }
```

`users` is a local application identity projection, not an authentication store. It contains no password, access token, refresh token, MFA secret, or Cognito client secret. A unique `cognito_sub` maps a validated Cognito identity to the internal `user_id` used by role assignments and audit records.

`event_role_assignments` stores privileged, event-scoped facts. A unique `(event_id, user_id, role)` constraint allows a user to hold more than one independent role for the same event. The authorization lookup is indexed by `(user_id, event_id, status)`. An assignment is effective only when it is active and within its optional validity window. Removing access is a soft revoke: the service changes `status` to `REVOKED` and records `revoked_at`, retaining the row for audit. Reassigning the same role reactivates that row and refreshes its grant metadata rather than inserting a duplicate. Assignment, revocation, and reactivation operations are idempotent.

An authenticated active user is a Customer by default. Customer access is derived from domain ownership such as `orders.customer_sub`, `tickets.customer_sub`, or an event registration—not from a `CUSTOMER` row for every user/event combination. This avoids duplicating business facts and avoids growth proportional to every possible user/event pair.

### Central policy model

Role assignments are facts stored in RDS. Action-to-role policy remains in version-controlled application code so developers can review and change authorization behavior in one place.

| Action | Required facts |
|---|---|
| `event:create` | Authenticated, active user |
| `event:update` | Active `ORGANIZER` assignment for the event |
| `event:publish` | Active `ORGANIZER` assignment for the event |
| `event-helper:assign` | Active `ORGANIZER` assignment for the event |
| `ticket:check-in` | Active `ORGANIZER` or `EVENT_HELPER` assignment for the event |
| `order:view` | Authenticated user owns the order |

### Authorization API endpoints

| Method | Path | Description | Caller |
|---|---|---|---|
| POST | `/authorization/decisions` | Evaluate an action against a resource | Backend services |
| GET | `/authorization/users/me` | Resolve the authenticated Cognito subject to the application user | Authenticated user |
| POST | `/authorization/events/{eventId}/role-assignments` | Assign Organizer or Event Helper | Organizer / system bootstrap |
| GET | `/authorization/events/{eventId}/role-assignments` | List active and historical event assignments | Organizer / Event Helper |
| PATCH | `/authorization/events/{eventId}/role-assignments/{assignmentId}` | Change validity or status | Organizer |
| DELETE | `/authorization/events/{eventId}/role-assignments/{assignmentId}` | Revoke an assignment idempotently | Organizer |
| GET | `/authorization/health` | Report policy-engine and database readiness without exposing secrets | Platform / load balancer |

An invalid or expired token returns `401`. A valid user without the required permission receives an `allowed: false` decision, which the calling service enforces as `403`. If the policy engine or its database cannot make a trustworthy decision, the caller returns `503` and performs no protected action. Calls use bounded timeouts, correlation IDs, structured logs without tokens, and no decision caching initially so revocation is visible on the next request.

### Event creator bootstrap

Creating an event and assigning its creator as Organizer spans two service-owned schemas, so it cannot use one database transaction. The operation must be idempotent and must not expose an organizer-less event as ready for use.

```mermaid
sequenceDiagram
    actor U as User
    participant EIS as Event & Inventory Service
    participant APS as Authorization Policy Engine
    participant EDB as event_inventory schema
    participant ADB as authorization schema

    U->>EIS: POST /events + access token
    EIS->>APS: Decide event:create
    APS-->>EIS: allowed
    EIS->>EDB: Create DRAFT_PENDING_AUTHORIZATION event
    EIS->>APS: Idempotently assign creator as ORGANIZER
    APS->>ADB: Insert or return existing assignment
    APS-->>EIS: Assignment active
    EIS->>EDB: Transition event to DRAFT
    EIS-->>U: Event created
```

If assignment fails, the event remains non-publishable and the service retries safely using the event id as the idempotency boundary. A later outbox-based workflow may replace the synchronous bootstrap if reliability or scale requires it.

### Current implementation and migration considerations

This document describes the **target architecture**. The current backend schema still contains `customers` and stores one `events.organizer_id` foreign key. It does not yet contain the target `authorization.users` or `authorization.event_role_assignments` tables.

Database migration remains a separate, explicitly reviewed change. A safe rollout is additive: introduce the identity and assignment tables, backfill Cognito subjects and existing organizers, temporarily reconcile old and new organizer representations, switch authorization reads to the policy engine, and remove the legacy organizer source only in a later cleanup migration. No cross-schema foreign key is introduced, and the old source is not removed until all consumers have cut over and consistency checks pass.

---

## Event & Inventory Service — `event_inventory` schema

The platform's core technical risk: owns events, their inventory (GA quantity or a seat map), and the concurrency-safe hold that guarantees a seat or quantity is never sold twice. Event-role assignments belong to the Authorization Policy Engine.

### Data model

```mermaid
erDiagram
    EVENTS ||--o{ INVENTORY_ITEMS : offers
    EVENTS ||--o{ SEATS : contains
    EVENTS ||--o{ INVENTORY_HOLDS : locks
    INVENTORY_ITEMS ||--o{ SEATS : "maps to (Tier 2 only)"
    INVENTORY_ITEMS ||--o{ INVENTORY_HOLDS : "reserved via"
    SEATS ||--o| INVENTORY_HOLDS : "held by"

    EVENTS {
        bigint event_id PK
        bigint created_by_user_id "logical ref -> authorization.users, no FK"
        varchar title
        text description
        varchar venue
        datetime starts_at
        enum tier "TIER1_GA, TIER2_SEATED"
        enum status "DRAFT, PUBLISHED, CANCELLED"
        datetime created_at
        datetime updated_at
    }
    INVENTORY_ITEMS {
        bigint inventory_item_id PK
        bigint event_id FK
        varchar name "e.g. General Admission"
        int total_qty
        int reserved_qty
        int sold_qty
        int price_cents
        int version "optimistic lock"
        datetime created_at
    }
    SEATS {
        bigint seat_id PK
        bigint event_id FK
        bigint inventory_item_id FK
        varchar seat_label "e.g. A12"
        enum status "AVAILABLE, HELD, SOLD"
        bigint hold_id FK "nullable"
        datetime updated_at
    }
    INVENTORY_HOLDS {
        bigint hold_id PK
        bigint event_id FK
        bigint inventory_item_id FK "nullable for seated"
        varchar customer_sub "Cognito sub"
        int quantity
        enum status "ACTIVE, CONFIRMED, RELEASED, EXPIRED"
        bigint order_id "logical ref -> checkout.orders, no FK"
        datetime expires_at
        datetime created_at
    }
```

### Domain model

```mermaid
classDiagram
    class Event {
        +Long eventId
        +Long createdByUserId
        +String title
        +String description
        +String venue
        +DateTime startsAt
        +Tier tier
        +EventStatus status
        +publish()
        +cancel()
        +updateDetails()
    }
    class InventoryItem {
        +Long inventoryItemId
        +Long eventId
        +String name
        +int totalQty
        +int reservedQty
        +int soldQty
        +int priceCents
        +int version
        +reserve(int qty)
        +release(int qty)
        +confirm(int qty)
        +availableQty() int
    }
    class Seat {
        +Long seatId
        +Long eventId
        +Long inventoryItemId
        +String seatLabel
        +SeatStatus status
        +hold(Long holdId)
        +release()
        +sell()
    }
    class InventoryHold {
        +Long holdId
        +Long eventId
        +Long inventoryItemId
        +String customerSub
        +int quantity
        +HoldStatus status
        +Long orderId
        +DateTime expiresAt
        +confirm(Long orderId)
        +release()
        +isExpired() bool
    }
    class Tier {
        <<enumeration>>
        TIER1_GA
        TIER2_SEATED
    }
    class EventStatus {
        <<enumeration>>
        DRAFT
        PUBLISHED
        CANCELLED
    }
    class SeatStatus {
        <<enumeration>>
        AVAILABLE
        HELD
        SOLD
    }
    class HoldStatus {
        <<enumeration>>
        ACTIVE
        CONFIRMED
        RELEASED
        EXPIRED
    }
    class EventInventoryService {
        <<service>>
        +createEvent(dto) Event
        +configureInventory(eventId, dto)
        +publishEvent(eventId)
        +reserveInventory(eventId, itemId, qty, seatIds) InventoryHold
        +confirmHold(holdId, orderId)
        +releaseHold(holdId)
    }

    Event "1" *-- "0..*" InventoryItem : offers
    Event "1" *-- "0..*" Seat : contains
    Event "1" *-- "0..*" InventoryHold : locks
    InventoryItem "1" o-- "0..*" Seat : maps to
    InventoryItem "1" <-- "0..*" InventoryHold : reserved via
    Seat "0..1" <-- "0..1" InventoryHold : held by
    EventInventoryService ..> Event : manages
    EventInventoryService ..> InventoryHold : manages
```

### API endpoints

| Method | Path | Description | Caller |
|---|---|---|---|
| POST | `/events` | Create a draft event (creator becomes Organiser) | Customer |
| GET | `/events` | Browse / search published events | Any |
| GET | `/events/{eventId}` | Event detail incl. live availability | Any |
| PUT | `/events/{eventId}` | Edit event details | Organiser |
| POST | `/events/{eventId}/publish` | Publish the event | Organiser |
| POST | `/events/{eventId}/cancel` | Cancel the event | Organiser |
| PUT | `/events/{eventId}/inventory` | Configure ticket quantity / seat map | Organiser |
| GET | `/events/{eventId}/seats` | Seat map with live status | Any |
| POST | `/events/{eventId}/inventory/hold` | Reserve seats / quantity (soft lock) | Customer |
| POST | `/holds/{holdId}/release` | Release a hold | Customer / internal sweep |
| POST | `/holds/{holdId}/confirm` | Confirm a hold as sold (sync, no-oversell path) | Checkout Service |

---

## Waiting Room / Queue Service — `queue` schema

Sits in front of Tier 2 on-sales only. Holds no inventory of its own — it just orders customers into a line and admits them in batches, checking availability against the Event & Inventory Service before letting anyone through.

### Data model

```mermaid
erDiagram
    QUEUE_SESSIONS ||--o{ QUEUE_ENTRIES : contains

    QUEUE_SESSIONS {
        bigint queue_session_id PK
        bigint event_id "logical ref -> event_inventory.events, no FK"
        datetime opens_at
        int admission_batch_size
        int admission_interval_sec
        enum status "CLOSED, OPEN, DRAINED"
    }
    QUEUE_ENTRIES {
        bigint queue_entry_id PK
        bigint queue_session_id FK
        varchar customer_sub "Cognito sub"
        bigint position
        enum status "WAITING, ADMITTED, IN_CHECKOUT, EXPIRED, LEFT"
        datetime joined_at
        datetime admitted_at "nullable"
        varchar admission_token "nullable"
        datetime token_expires_at "nullable"
    }
```

### Domain model

```mermaid
classDiagram
    class QueueSession {
        +Long queueSessionId
        +Long eventId
        +DateTime opensAt
        +int admissionBatchSize
        +int admissionIntervalSec
        +SessionStatus status
        +open()
        +drain()
    }
    class QueueEntry {
        +Long queueEntryId
        +Long queueSessionId
        +String customerSub
        +long position
        +EntryStatus status
        +DateTime joinedAt
        +DateTime admittedAt
        +String admissionToken
        +DateTime tokenExpiresAt
        +admit()
        +expire()
        +leave()
    }
    class SessionStatus {
        <<enumeration>>
        CLOSED
        OPEN
        DRAINED
    }
    class EntryStatus {
        <<enumeration>>
        WAITING
        ADMITTED
        IN_CHECKOUT
        EXPIRED
        LEFT
    }
    class WaitingRoomService {
        <<service>>
        +joinQueue(eventId, customerSub) QueueEntry
        +getMyStatus(eventId, customerSub) QueueEntry
        +admitNextBatch(queueSessionId)
        +configureSession(eventId, dto) QueueSession
    }

    QueueSession "1" *-- "0..*" QueueEntry : holds
    WaitingRoomService ..> QueueSession : manages
    WaitingRoomService ..> QueueEntry : manages
```

### API endpoints

| Method | Path | Description | Caller |
|---|---|---|---|
| PUT | `/events/{eventId}/queue/config` | Configure on-sale time & admission rate | Organiser |
| POST | `/events/{eventId}/queue/join` | Join the waiting room | Customer |
| GET | `/events/{eventId}/queue/me` | My live position & status | Customer |
| POST | `/events/{eventId}/queue/admit-next` | Admit the next batch (scheduled) | Internal (scheduled task) |

---

## Checkout & Payment Service — `checkout` schema

Turns a confirmed hold into a paid order using a simulated, tokenized payment — no real card data ever reaches this schema. Owns the sales figures and attendee contact details organisers see on their dashboard.

### Data model

```mermaid
erDiagram
    ORDERS ||--o{ ORDER_ITEMS : contains
    ORDERS ||--o{ PAYMENTS : "paid via"

    ORDERS {
        bigint order_id PK
        bigint event_id "logical ref -> event_inventory.events, no FK"
        varchar customer_sub "Cognito sub"
        varchar customer_email
        bigint hold_id "logical ref -> event_inventory.inventory_holds, no FK"
        enum status "PENDING, PAID, FAILED, CANCELLED"
        int total_amount_cents
        char currency
        datetime created_at
        datetime paid_at "nullable"
    }
    ORDER_ITEMS {
        bigint order_item_id PK
        bigint order_id FK
        bigint inventory_item_id "logical ref -> event_inventory.inventory_items, no FK"
        bigint seat_id "logical ref -> event_inventory.seats, nullable, no FK"
        varchar description
        int quantity
        int unit_price_cents
    }
    PAYMENTS {
        bigint payment_id PK
        bigint order_id FK
        varchar payment_token "simulated, tokenized"
        enum status "AUTHORIZED, CAPTURED, FAILED"
        int amount_cents
        datetime processed_at
    }
```

### Domain model

```mermaid
classDiagram
    class Order {
        +Long orderId
        +Long eventId
        +String customerSub
        +String customerEmail
        +Long holdId
        +OrderStatus status
        +int totalAmountCents
        +String currency
        +DateTime createdAt
        +DateTime paidAt
        +markPaid()
        +markFailed()
        +cancel()
    }
    class OrderItem {
        +Long orderItemId
        +Long orderId
        +Long inventoryItemId
        +Long seatId
        +String description
        +int quantity
        +int unitPriceCents
    }
    class Payment {
        +Long paymentId
        +Long orderId
        +String paymentToken
        +PaymentStatus status
        +int amountCents
        +DateTime processedAt
        +capture()
        +fail()
    }
    class OrderStatus {
        <<enumeration>>
        PENDING
        PAID
        FAILED
        CANCELLED
    }
    class PaymentStatus {
        <<enumeration>>
        AUTHORIZED
        CAPTURED
        FAILED
    }
    class CheckoutService {
        <<service>>
        +createOrder(eventId, holdId, customerSub) Order
        +submitPayment(orderId, simulatedCardToken) Payment
        +getOrder(orderId) Order
        +listMyOrders(customerSub) List~Order~
        +getSalesSummary(eventId) SalesSummary
        +publishOrderPaid(orderId)
    }

    Order "1" *-- "1..*" OrderItem : contains
    Order "1" *-- "1" Payment : paid via
    CheckoutService ..> Order : manages
    CheckoutService ..> Payment : manages
```

### API endpoints

| Method | Path | Description | Caller |
|---|---|---|---|
| POST | `/orders` | Create an order from a hold | Customer |
| POST | `/orders/{orderId}/payment` | Submit simulated, tokenized payment | Customer |
| GET | `/orders/{orderId}` | Order detail | Customer (owner) / Organiser |
| GET | `/customers/me/orders` | My order history | Customer |
| GET | `/events/{eventId}/orders/summary` | Sales dashboard data | Organiser / Helper |
| GET | `/events/{eventId}/attendees` | Attendee & order export | Organiser |

---

## Ticket Issuance & Validation Service — `ticketing` schema

Issues the QR-coded ticket after payment and is the single source of truth at the door: the Scanner App and the Buyer App's own "my tickets" view both read ticket state from here, so a ticket can never be checked in twice.

### Data model

```mermaid
erDiagram
    TICKETS ||--o{ CHECK_IN_LOGS : records

    TICKETS {
        bigint ticket_id PK
        bigint order_id "logical ref -> checkout.orders, no FK"
        bigint order_item_id "logical ref -> checkout.order_items, no FK"
        bigint event_id "logical ref -> event_inventory.events, no FK"
        varchar customer_sub "Cognito sub"
        varchar customer_email
        bigint seat_id "logical ref -> event_inventory.seats, nullable, no FK"
        varchar qr_token "unique"
        enum status "ISSUED, CHECKED_IN, VOID"
        datetime issued_at
        datetime checked_in_at "nullable"
        varchar checked_in_by_sub "nullable, Cognito sub"
    }
    CHECK_IN_LOGS {
        bigint log_id PK
        bigint ticket_id FK
        varchar scanned_by_sub "Cognito sub"
        enum result "SUCCESS, DUPLICATE, INVALID, WRONG_EVENT"
        datetime scanned_at
    }
```

### Domain model

```mermaid
classDiagram
    class Ticket {
        +Long ticketId
        +Long orderId
        +Long orderItemId
        +Long eventId
        +String customerSub
        +String customerEmail
        +Long seatId
        +String qrToken
        +TicketStatus status
        +DateTime issuedAt
        +DateTime checkedInAt
        +String checkedInBySub
        +checkIn(scannedBySub) CheckInResult
        +void()
    }
    class CheckInLog {
        +Long logId
        +Long ticketId
        +String scannedBySub
        +CheckInResult result
        +DateTime scannedAt
    }
    class TicketStatus {
        <<enumeration>>
        ISSUED
        CHECKED_IN
        VOID
    }
    class CheckInResult {
        <<enumeration>>
        SUCCESS
        DUPLICATE
        INVALID
        WRONG_EVENT
    }
    class TicketService {
        <<service>>
        +issueTicketsForOrder(orderPaidEvent) List~Ticket~
        +validateTicket(eventId, qrToken, scannedBySub) CheckInResult
        +searchTickets(eventId, query) List~Ticket~
        +getCheckInStats(eventId) CheckInStats
        +getMyTickets(customerSub) List~Ticket~
    }

    Ticket "1" *-- "0..*" CheckInLog : logs
    TicketService ..> Ticket : manages
    TicketService ..> CheckInLog : records
```

### API endpoints

| Method | Path | Description | Caller |
|---|---|---|---|
| GET | `/customers/me/tickets` | My tickets | Customer |
| GET | `/tickets/{ticketId}` | Ticket detail + QR | Customer (owner) |
| POST | `/tickets/validate` | Scan & validate a QR code | Helper / Organiser |
| GET | `/tickets/search` | Manual lookup by name / email / order ID | Helper / Organiser |
| GET | `/events/{eventId}/checkin-stats` | Live check-in count | Organiser / Helper |
| *(async)* | SQS `order-events` → `OrderPaid` | Consumer: issues ticket(s), sends email | System |

---

## Tier 2 purchase — sync vs. async in one picture

The flow that justifies every choice above: the queue and the inventory hold are synchronous because correctness can't wait; publishing to SQS and issuing the ticket happen after the customer already has a confirmed, paid order.

```mermaid
sequenceDiagram
    actor C as Customer (Buyer App)
    participant WR as Waiting Room / Queue Service
    participant EIS as Event & Inventory Service
    participant CPS as Checkout & Payment Service
    participant SQS as SQS: order-events
    participant TIV as Ticket Issuance & Validation Service

    C->>WR: POST /queue/join
    WR-->>C: queue position (polls /queue/me)
    WR->>WR: admission worker admits next batch
    WR-->>C: ADMITTED + admission token

    C->>EIS: POST /inventory/hold (seats/qty, admission token)
    EIS->>EIS: reserve within DB transaction (no oversell)
    EIS-->>C: hold created, expiresAt

    C->>CPS: POST /orders (holdId)
    CPS-->>C: order PENDING
    C->>CPS: POST /orders/{id}/payment (simulated)
    CPS->>EIS: POST /holds/{id}/confirm  (sync — must succeed before order is PAID)
    EIS-->>CPS: hold CONFIRMED
    CPS->>CPS: mark order PAID
    CPS-->>C: order PAID
    CPS->>SQS: publish OrderPaid  (async — decouples issuance)
    SQS-->>TIV: deliver OrderPaid
    TIV->>TIV: issue ticket(s), generate QR
    TIV-->>C: email ticket with QR (async)
```

A Tier 1 purchase runs the same path with the Waiting Room steps skipped entirely — `POST /inventory/hold` succeeds immediately since there's no queue to admit from.

---

*Companion document to "OneStage — User Stories & Use-Case Diagrams." IDs, enum values, and endpoint names here are the vocabulary the user stories' acceptance criteria assume — e.g. CU-09's "no seat is ever confirmed to two buyers" is exactly what `InventoryHold` plus the synchronous `/holds/{id}/confirm` call is designed to guarantee.*
