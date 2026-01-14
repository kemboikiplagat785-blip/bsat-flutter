# TransactionController README

Location: [lib/controllers/transaction_controller.dart](../lib/controllers/transaction_controller.dart)

## Role
Coordinates the full payment-to-transaction pipeline: parse incoming M-PESA SMS, resolve the right offer, dial USSD (standard or advanced), persist outcomes, and emit replies/side effects.

## End-to-End Flow (makeTransaction)
1. Housekeeping: optional purge old transactions, trim SMS body.
2. Parse inputs: transaction id, customer number, amount, sender name.
3. Guards: blacklist check; optional forwarding branch; pause if offers flagged as changed; reject invalid numbers/Airtel.
4. Offer resolution: find USSD, SIM slot, retry/advanced flags; ensure subscription/token/auto-renew is in place.
5. Compounding: if exact offer missing, attempt to combine amounts.
6. Offer state: stop if offer inactive/paused.
7. Execution: if advanced and app is inactive, enqueue; else dial via PhoneService (advanced or normal) and derive status.
8. Persist: record transaction in SQLite with status, reply, metadata.
9. Notify: send reply text, optional contact auto-save, and return early if forwarding handled it.

## Key Collaborators
- Phone/USSD: `PhoneService` (advanced and normal requests)
- SMS parsing: helpers in `utils/constants.dart` and related parsers
- Persistence: `SQLiteService` (transactions table)
- Preferences/flags: `SharedPreferencesService`
- Payments/subscription: `PaymentOps`
- Contacts: `ContactsService` (auto-save)
- Forwarding and skills: `sms_service.dart`, `skills.dart`

## Data and State
- Reads SMS payload (`Telephony.SmsMessage`), shared prefs flags (auto-delete, auto-save, offers changed, tokens, auto-renew, active state), and subscription status.
- Writes transaction rows to SQLite; may mutate token balances/subscription state via PaymentOps; may add contacts.

## Extension Points
- Add new blacklist/validation rules before offer resolution.
- Plug alternative forwarding logic in the forwarding check.
- Add new USSD execution strategies inside the advanced/normal branching.
- Emit analytics or logging hooks after persistence.

## Testing Tips
- Unit-test parsing and decision branches by stubbing SharedPreferencesService, SQLiteService, PhoneService, and PaymentOps.
- For advanced USSD paths, cover the app-inactive branch to ensure queuing works.
- Use fake SMS bodies to assert correct status mapping (blacklisted, paused, unavailable, hasOkoa, done, error).
