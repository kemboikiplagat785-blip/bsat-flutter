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




































Received — I'll review your codebase at a high level and give concrete, prioritized software design recommendations and practical next steps you (or collaborators) can follow so the project is easier to understand, extend, test, and reuse.
Plan (brief)
Inspect the general layout from the workspace you provided and the sample lib/services/client_service.dart.
Provide concrete design principles and why they matter for your codebase.
Map the principles to concrete, prioritized changes and small actionable examples you can apply immediately.
Offer follow-up tasks I can implement for you (refactors, DI, tests, UI fixes, etc).
Checklist (what I'll cover)
High-level architecture & layering recommendations
Coding/construction guidelines (DI, immutability, pure functions, asynchronous patterns)
Module/feature organization and public API stability
Error handling, logging and observability
Tests and CI suggestions
Flutter-specific guidance (state management, scrolling, lazy lists, controllers, permissions)
Onboarding & repository hygiene (README, contributing, formatting, changelog)
Concrete, prioritized refactor ideas referencing lib/services/client_service.dart
Offer to implement selected changes
Recommendations and rationale
Single Responsibility Principle (SRP)
Every class/file should do one thing. E.g., ClientService should only encapsulate client-related business logic. Persistence details should be abstracted behind a repository or an injected data-access interface.
Why: Easier to test, replace, or reuse. Smaller classes are simpler to reason about.
Actionable:
Extract a ClientRepository interface and keep SQLiteClientRepository as an implementation that uses SQLiteService.
Make ClientService depend on ClientRepository (constructor injection), not directly on SQLiteService.
Dependency Injection (DI) and Inversion of Control
Avoid constructing dependencies inside classes (e.g., final SQLiteService _sqliteService = SQLiteService();).
Why: Makes classes testable and lets you swap implementations (mock DB, remote, in-memory) easily.
Actionable:
Add constructors such as ClientService({required ClientRepository repository}) and provide a default provider or a top-level locator (ServiceLocator, Provider, GetIt).
Use scoped DI in Flutter (Provider or Riverpod) for UI.
Clear layering / separation of concerns
Typical useful layers for this project:
Presentation (screens, widgets)
State/Controller (TransactionController, ClientController) — mapping UI interaction to business logic
Domain/Use-cases (optional): pure business rules and mapping
Data/Repositories (SQLite/HTTP/FCM)
Platform/Integration (platform channels, permissions)
Why: Each layer has a responsibility; replacing SQLite, adding tests, or changing UI becomes straightforward.
Define small interfaces and use DTOs / Mappers
Have small well-defined data transfer objects for DB rows and external API payloads.
Use mappers to convert DB maps -> models and vice versa. Keep model constructors simple.
Why: Changes in DB schema or API don't force ripples through UI code.
Error handling and result types
Prefer explicit error handling patterns:
Use Result<T, E> (either with packages or simple classes) or throw typed exceptions and document them.
Avoid returning null where possible; use Option/Either patterns or typed responses.
Why: Makes failure modes explicit and easier to test/handle in UI.
Asynchrony & concurrency
Make async flows explicit with async/await and cancelling support (e.g., when a screen is disposed).
Avoid calling print for production logging; use a logger with levels that can be toggled.
For DB writes and long operations, consider using background isolates or chunked operations (contacts transfer is already chunked).
Consistent naming and small, pure helpers
Keep naming consistent: e.g., getClientByPhone, getAllClients are good. Keep parameter names clear (phoneNumber vs formattedPhone).
Keep small helper functions pure where possible — easier to test.
State management and controllers
For project-wide controllers (e.g., TransactionController), choose an explicit state-management approach (Provider, Riverpod, GetX, Bloc).
Expose minimal public API: e.g., TransactionController methods should return Futures or Streams and have clear lifecycle/cleanup.
How to reuse controllers: create providers (ChangeNotifierProvider or Riverpod provider) and read them from widgets. Avoid creating new instances in multiple places.
UI / UX considerations (relevant to your earlier messages)
List rendering: use ListView.builder for lazy loading; wire a ScrollController to the Scrollbar (thumbVisibility requires explicit controller).
Provide pagination/lazy-load APIs in controllers/repositories.
Make large parts scrollable: wrap with CustomScrollView or SingleChildScrollView where appropriate.
Provide a small style system for scrollbars and shared widgets (so you can style them app-wide).
Database migration & schema evolution
Introduce a small migration mechanism: keep schema versions and apply ALTER TABLE logic in a central DB helper (SQLiteService).
Use column existence checks (you already do some) but centralize.
Testing, CI, and code quality
Unit tests for services/repositories.
Widget tests for main screens.
Integration tests for full flows (contacts export/import).
Add CI (GitHub Actions) to run analyzer, formatter, tests on PRs.
Use analysis_options.yaml rules and format enforcement with dart format.
Documentation & Onboarding
Add:
README with “Getting started” and architecture overview.
CONTRIBUTING.md with code style, how to run, how to test.
CODEOWNERS or maintainers.
API docs for server contracts and important flows (contacts transfer, secure FCM usage).
A small diagram: show flow for pairing, message sending, contacts transfer.
Packaging & modularization
Consider splitting big features into packages (e.g., bsat_core, bsat_ui, bsat_services) if the app grows or is reused by others.
Use lib/src + public lib exports so you can hide internals and expose a stable API.
Security & privacy
Sensitive flows (contacts transfer, messages) must be explicit about encryption and token usage (you already use JWT and FCM).
Avoid logging sensitive data in production.
Add permission rationale strings and clear flows for READ_PHONE_STATE and contact permissions.
Observability & telemetry
Capture errors (Crashlytics), events (analytics), and logs.
Provide structured logs from services (timestamp, level, context) rather than ad-hoc prints.
Concrete, prioritized refactor suggestions (quick wins)
Constructor DI for ClientService
Change ClientService to accept a ClientRepository (or SQLiteService) via constructor instead of creating _sqliteService internally.
Benefit: easy to unit test and mock DB in tests.
Extract ClientRepository interface and SQLiteClientRepository implementation
Keep DB SQL inside the repository so service doesn't know schema.
Replace prints with a logger and add log levels
Use package:logger or a small wrapper to control verbosity.
Add unit tests for ClientService behavior (insert/update logic) and for SQLiteClientRepository queries (in-memory DB if needed).
Improve nullability contracts and error returns
Return typed results or throw documented exceptions.
Add paging and ScrollController to list screens
Controllers should expose fetchPage({int pageSize, int? afterId}).
UI should pass ScrollController to Scrollbar.
Add documentation for backend endpoints used by the app (including transfer chunk sizes & encoding).
Mapping recommendations to the sample lib/services/client_service.dart
Observations:
The class directly instantiates SQLiteService.
There are print statements and some null returns (getClientByPhone returns Future<Client?>) — fine, but the interface can be clearer.
The class mixes DB schema migration concern (_ensureAlternativePhoneNumberColumn) with business logic.
Suggested refactors:
Introduce ClientRepository and move _ensureAlternativePhoneNumberColumn() into the repository (or SQLiteService migration).
Make insertClient return a domain-specific Result or throw a ClientAlreadyExists typed exception.
Remove console prints; use logger.debug/info.
How to onboard contributors (practical)
Add README.md sections:
Project purpose, architecture diagram, how to run locally.
How to run tests and linters.
Add CONTRIBUTING.md: PR process, style guide, how to run an app, how to add migrations.
Add code samples for common tasks (e.g., how to get TransactionController using Provider).
Add a simple “developer environment setup” script or documented steps.
Suggested immediate next steps I can do for you (pick one or more)
A: Refactor ClientService to accept dependency injection (constructor) and add an interface for the repository.
B: Create a ClientRepository and SQLiteClientRepository and move migration logic to repository.
C: Add a simple logger wrapper and replace print in ClientService.
D: Add unit tests for ClientService using a mock repository.
E: Create a short CONTRIBUTING.md and update README with architecture overview.
F: Implement ScrollController + styled Scrollbar pattern and a paginated list example for inbox/transactions screens.
If you want, I can implement one of the above right now. Tell me which option(s) to start with (I recommend A then B then D), and I will:
produce the patch,
run analyzer/tests (where applicable),
iterate until clean.
Which one should I start implementing now?