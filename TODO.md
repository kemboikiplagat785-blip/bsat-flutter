# BSAT Maintainability TODO

## Quick Wins (Do First)

- [ ] **A. Add dependency injection for `ClientService`**
  - [ ] Stop instantiating `SQLiteService` inside `ClientService`.
  - [ ] Pass dependencies via constructor (repository or DB abstraction).
  - [ ] Wire service creation from app-level provider/locator.

- [ ] **B. Extract repository layer for clients**
  - [ ] Create `ClientRepository` interface (read/write/search methods).
  - [ ] Implement `SQLiteClientRepository` for SQL operations.
  - [ ] Move schema concerns (like `alternativePhoneNumber` column checks) out of service logic.

- [ ] **C. Replace `print` with structured logging**
  - [ ] Standardize on `BsatLogger` in services/controllers.
  - [ ] Add log levels (`debug`, `info`, `warn`, `error`).
  - [ ] Remove sensitive payloads from logs.

- [ ] **D. Add unit tests for client logic**
  - [ ] Test `insertClient` behavior (existing phone vs new insert).
  - [ ] Test update paths for name changes.
  - [ ] Use mocks/fakes for repository.

- [ ] **E. Improve contributor onboarding docs**
  - [ ] Update `README.md` with architecture and run/test steps.
  - [ ] Add `CONTRIBUTING.md` (style, PR checks, migration rules).
  - [ ] Document common controller/service usage patterns.

- [ ] **F. Standardize list UX patterns**
  - [ ] Add pagination/lazy-loading support in list screens.
  - [ ] Always pair visible `Scrollbar` with explicit `ScrollController`.
  - [ ] Build shared styled scrollbar widget/theme.

## Core Design Principles to Apply

- [ ] **Single Responsibility Principle (SRP)**
  - [ ] Keep each class focused: UI, business logic, data access, and platform integration separated.

- [ ] **Dependency Inversion**
  - [ ] Depend on interfaces (`Repository`, `ServiceContract`) not concrete DB/network classes.

- [ ] **Clear Layering**
  - [ ] Enforce boundaries: `screens/widgets` -> `controllers/state` -> `services/use-cases` -> `repositories` -> `sqlite/http/platform`.

- [ ] **Explicit contracts and mapping**
  - [ ] Use typed DTO/model mapping for API and DB boundaries.
  - [ ] Keep serialization/parsing in one place per feature.

- [ ] **Predictable error handling**
  - [ ] Use typed failures/exceptions and handle them in UI state.
  - [ ] Avoid silent null fallbacks for critical flows.

## Data & Persistence

- [ ] Centralize DB migrations in `SQLiteService` with schema versioning.
- [ ] Document table/column ownership and migration history.
- [ ] Add regression tests for migration paths.

## Flutter UI/State Quality

- [ ] Choose and enforce one primary state approach per module (`Provider`/Riverpod/etc.).
- [ ] Reuse controllers through DI/providers, not ad-hoc instantiation.
- [ ] Use `ListView.builder`/lazy strategies for large SMS/transaction lists.
- [ ] Keep page sections scrollable so controls and lists scale on small screens.

## Reliability, Security, and Observability

- [ ] Add retries/backoff for network-sensitive flows (FCM/contact transfer/chunk upload).
- [ ] Sanitize logs and avoid exposing tokens, contact payloads, or SMS content unnecessarily.
- [ ] Add structured diagnostics around pairing, client connection, and transfer state.
- [ ] Track critical events/errors in analytics/crash reporting.

## Testing and CI

- [ ] Add unit tests for services/repositories/controllers.
- [ ] Add widget tests for high-traffic screens (inbox, transactions, clients).
- [ ] Add CI workflow to run `flutter analyze`, format check, and tests on PRs.

## Suggested Implementation Order

- [ ] 1) A -> B -> D (DI + repository + tests)
- [ ] 2) C + migration centralization
- [ ] 3) F + state management consistency updates
- [ ] 4) Docs (`README.md`, `CONTRIBUTING.md`) and CI hardening

