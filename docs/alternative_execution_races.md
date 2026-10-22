# Alternative execution coordination limits

This document describes the guarantees available in the Flutter application.
It does not establish behavior of the deployed `api.$kBaseUrl` service. No
backend coordination or carrier idempotency has been verified.

## Race A: Confirmation arrives while Phone C is about to execute

**Protected locally:** Phone B persists its primary confirmation and prevents
its own delayed scheduler from dispatching an alternative after it observes
that confirmation. Phone C stores a durable alternative job before execution.

**Still unprotected:** A job already delivered to C has no remotely checked
authorization version or revocation token. C can act on stale local state
before learning that B confirmed the primary transaction.

**Possible consequence:** Both the primary and alternative purchase may be
processed.

**Evidence/architecture needed:** A backend-coordinated, one-time authorization
checked immediately before C submits; ideally an atomic shared state transition
that makes primary confirmation and alternative authorization mutually
exclusive. Deployed support is unverified.

## Race B: Confirmation arrives after C crosses the submission boundary

**Protected locally:** C persists execution intent before dialing and treats
unknown results as ambiguous rather than automatically resubmitting them.

**Still unprotected:** Once the request reaches the carrier, a later local or
backend cancellation cannot guarantee that Safaricom will not process it.

**Possible consequence:** A purchase can complete after another device believes
the alternative was canceled.

**Evidence/architecture needed:** Carrier-supported idempotency or cancellation
semantics could reduce this risk. Backend authorization alone cannot eliminate
the post-submission race.

## Race C: Different Flutter isolates

**Protected locally:** Each isolate serializes its own USSD calls. SQLite job
state uses conditional updates to limit duplicate work in one local database.

**Still unprotected:** Foreground, service, SMS callback, and FCM callback
isolates do not share an isolate-local mutex. Their separate read/claim/write
sequences are not a cross-isolate atomic authorization boundary.

**Possible consequence:** A confirmation and a USSD submit can race, or two
isolates can make decisions from different snapshots.

**Evidence/architecture needed:** A single native execution owner plus durable
cross-isolate claims can reduce local collisions. Cross-device eligibility
still needs shared backend coordination.

## Race D: Offline or delayed device messages

**Protected locally:** C deduplicates complete alternative jobs by forwarding
job ID and reuses persisted state on redelivery.

**Still unprotected:** C may be offline or receive a delayed/replayed message
after B or A has moved on. Local deduplication cannot establish current remote
eligibility.

**Possible consequence:** C may execute an expired or superseded alternative.

**Evidence/architecture needed:** Authenticated authorization with expiry,
monotonic version, and one-time consumption from shared state. Deployed backend
support is unverified.

## Race E: Process death and recovery

**Protected locally:** The app persists the job before submission and
reconciles an interrupted executing job as ambiguous. Ambiguous outcomes are
not automatically redialed.

**Still unprotected:** Process death can occur between carrier submission,
carrier response, SMS arrival, and local persistence. The app may be unable to
prove whether the purchase completed.

**Possible consequence:** A manual retry may duplicate a purchase if external
evidence remains unavailable.

**Evidence/architecture needed:** Carrier transaction references and
idempotency, durable operating-system execution ownership, or authoritative
carrier reconciliation would improve certainty. A backend alone cannot infer a
carrier result that was never reported to it.
