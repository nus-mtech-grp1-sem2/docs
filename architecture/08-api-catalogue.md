# Appendix: API Catalogue

Every business endpoint as built on 17 October 2026, taken from the Express routes in `backend-repo: services/*/src`. Clients call `https://<distribution>/api/<service><path>`: CloudFront forwards `/api/*` to the ALB, and Kong strips `/api/<service>` before forwarding. Every service also answers `GET /health`.

**Caller and authorisation**:
- **Public**: no token needed.
- **Signed in**: any valid Cognito access token (every signed-in user is a Customer).
- **Owner**: the signed-in user must own the resource (order, hold, ticket).
- **Organiser** or **Helper**: an accepted membership in `event_team_memberships` for that event.
- **Event owner**: the event's creator.
- **Scanner session**: the HMAC-signed, event-scoped session from `POST /scanner/sessions`.
- **Internal**: service-to-service only, using a shared secret header.
- **Admitted**: the caller's queue entry for the event is `ADMITTED` with an unexpired admission token, sent in the request body.

POST routes on `queue` and `order` are rate limited at Kong to 60 per minute per client IP.

## Event service (`/api/event`)

Table: Event service endpoints

| Method | Path | Purpose | Caller |
|---|---|---|---|
| GET | `/events` | Browse and search published events | Public |
| GET | `/venues` | List known venues | Public |
| GET | `/events/:eventId` | Event detail | Public |
| GET | `/events/:eventId/seats` | Seat map with live status | Public |
| GET | `/events/:eventId/image` | Event photo | Public |
| GET | `/events/manage` | Events the caller organises | Signed in |
| GET | `/helper/shifts` | Events the caller helps at | Signed in |
| POST | `/events` | Create a draft event; creator becomes Organiser | Signed in |
| PUT | `/events/:eventId` | Edit a draft's details; changing the tier clears its inventory (refused once anything is reserved or sold) | Organiser |
| PUT | `/events/:eventId/available-buyers` | Set how many buyers the queue admits at once; allowed while on sale, until the event starts | Organiser |
| PUT | `/events/:eventId/image` | Upload the event photo | Organiser |
| POST | `/events/:eventId/publish` | Publish | Organiser |
| GET | `/events/:eventId/cancellation-impact` | Tickets and buyers a cancel would affect | Organiser |
| POST | `/events/:eventId/cancel` | Cancel; void tickets; refund orders (needs `confirm: true` once tickets are sold) | Organiser |
| DELETE | `/events/:eventId` | Delete a draft event with no reservation history | Organiser |
| GET | `/events/:eventId/users` | Users who can be invited | Organiser |
| GET | `/events/:eventId/team-members` | Team roster | Organiser |
| PATCH | `/events/:eventId/team-members/:userSub` | Change a member's role | Event owner (organisers); Organiser (helpers) |
| DELETE | `/events/:eventId/team-members/:userSub` | Remove a member (soft revoke to `REVOKED`; cannot remove yourself) | Event owner (organisers); Organiser (helpers) |
| POST | `/events/:eventId/invitations` | Invite a user by email as Organiser or Helper | Organiser |
| GET | `/team-invitations` | The caller's pending invitations | Signed in |
| POST | `/team-invitations/:membershipId/:decision` | Accept or reject an invitation | Signed in (invitee) |

## Inventory service (`/api/inventory`)

Table: Inventory service endpoints

| Method | Path | Purpose | Caller |
|---|---|---|---|
| GET | `/events/:eventId/seats` | Seat map with layout data | Signed in |
| GET | `/events/:eventId/zones` | Zones (sections) with availability, grid position and stage pieces | Signed in |
| GET | `/events/:eventId/inventory` | Full inventory configuration | Organiser |
| PUT | `/events/:eventId/inventory` | Configure zones, grid and seats (cannot shrink below reserved or sold; seated maps at most 400 seats; general-admission sections take an explicit quantity) | Organiser |
| PUT | `/events/:eventId/stage` | Replace the stage layout (up to 5 pieces, not overlapping zones) | Organiser |
| PATCH | `/events/:eventId/seats` | Switch up to 10,000 seats on (`AVAILABLE`) or off (`BLOCKED`) in one request | Organiser |
| PATCH | `/events/:eventId/seats/:seatId` | Block, unblock or tag a seat | Organiser |
| POST | `/events/:eventId/holds` | Create a hold directly (not used by the SPA; see AISS-12) | Signed in |
| POST | `/holds/:holdId/release` | Release a hold (not used by the SPA) | Owner |
| POST | `/holds/:holdId/confirm` | Confirm a hold (not used by the SPA) | Owner |

## Queue service (`/api/queue`)

Table: Queue service endpoints

| Method | Path | Purpose | Caller |
|---|---|---|---|
| GET | `/events/:eventId/queue` | Queue status and waiting count (404 until the first join); also sets the session `OPEN` or `CLOSED` from the event's status and start time | Public |
| PUT | `/events/:eventId/queue/config` | Set opening time, batch size and interval. Kept for compatibility: the SPA does not call it, and the opening time no longer gates joining (AISS-12) | Organiser |
| POST | `/events/:eventId/queue/join` | Join the queue of a published event, either tier; the first join creates the session | Signed in |
| GET | `/events/:eventId/queue/me` | My position, status and admission token (polled every 3 s) | Signed in |
| DELETE | `/events/:eventId/queue/me` | Leave the queue or release an admitted place (refused once in checkout) | Signed in |
| POST | `/events/:eventId/queue/admit-next` | Admit the next batch now | Organiser, or Internal (`x-internal-token`, used by the order service) |

## Order service (`/api/order`)

Table: Order service endpoints

| Method | Path | Purpose | Caller |
|---|---|---|---|
| POST | `/orders` | Reserve seats or a quantity (at most 50 tickets) and create a `PENDING` order in one transaction | Admitted (both tiers) |
| POST | `/orders/:orderId/payment-requests` | Queue a mock payment; answers 202 | Owner |
| POST | `/orders/:orderId/payment` | Synchronous mock payment (kept for compatibility) | Owner |
| GET | `/orders/:orderId` | Order detail and status (polled during payment) | Owner or Organiser |
| POST | `/orders/:orderId/cancel` | Cancel an unpaid order and release its hold | Owner |
| GET | `/customers/me/orders` | My orders | Signed in |
| GET | `/events/:eventId/orders/summary` | Sales dashboard figures | Organiser or Helper |
| GET | `/events/:eventId/attendees` | Attendee list (used by the SPA) | Organiser |

## Ticket service (`/api/ticket`)

Table: Ticket service endpoints

| Method | Path | Purpose | Caller |
|---|---|---|---|
| GET | `/customers/me/tickets` | My tickets with QR data and seat label (a real seat, or a general-admission section number such as A12); polled every 5 s after payment | Signed in |
| GET | `/customers/me/orders/:orderId/confirmation` | Ticket and email status for one order | Owner |
| GET | `/tickets/:ticketId` | Ticket detail | Owner |
| POST | `/scanner/sessions` | Start an event-scoped scanner session | Helper or Organiser |
| DELETE | `/scanner/sessions/current` | End the scanner session (stateless; always 204) | Any |
| POST | `/tickets/validate` | Check in a ticket by QR token or ticket id | Scanner session |
| GET | `/tickets/search` | Manual lookup by name, email or order id | Scanner session |
| GET | `/events/:eventId/checkin-stats` | Live check-in counts | Scanner session, or Organiser/Helper |
| GET | `/events/:eventId/attendees` | Attendee list (duplicate of the order service's; not used by the SPA) | Organiser |
| GET | `/events/:eventId/orders/summary` | Sales summary (duplicate of the order service's; not used by the SPA) | Organiser |
| POST | `/internal/orders/:orderId/issue-tickets` | Issue tickets directly (local fallback when SQS is not configured; disabled in AWS) | Internal (`x-ticket-internal-secret`) |

## Notification service (internal only)

The notification service has no Kong route: it is reachable only over Service Connect, at `http://notification:3006`. Every `/notifications/*` route requires `INTERNAL_API_TOKEN` in the `x-internal-token` header and answers 401 without it (AISS-03, resolved).

Table: Notification service endpoints

| Method | Path | Purpose | Caller |
|---|---|---|---|
| POST | `/notifications/order-confirmation` | Send one email per ticket; idempotent per ticket | Internal (ticket service) |
| POST | `/notifications/event-cancellation` | Send a cancellation email for one order | Internal (ticket service) |
| GET | `/notifications/:orderId` | Delivery records for an order | Internal |

## Auth service (`/api/auth`)

Only `GET /health`. See AISS-12.

## Asynchronous interfaces

Table: Message contracts

| Message | Queue | Producer | Consumer | Fields (version 1) |
|---|---|---|---|---|
| `PaymentRequested` | `onestage-payment-requests` | order API | order worker | `type`, `version`, `orderId`, `customerSub` |
| `OrderPaid` | `onestage-order-events` | order worker | ticket service | `type`, `version`, `occurredAt`, `orderId`, `eventId`, `customerSub`, `customerEmail`, `customerName`, `paidAt`, `items[]` (`order_item_id`, `seat_id`, `quantity`, …) |
| `CustomerAdmitted` | `onestage-customer-admitted` | queue scheduler | none yet | `type`, `version`, `occurredAt`, `queueEntryId`, `eventId`, `customerSub`, `tokenExpiresAt` |
