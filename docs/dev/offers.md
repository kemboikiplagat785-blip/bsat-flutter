# Managing Offers

## Add a New Offer (in-app)
1) Open the app → Dashboard → “My tools” → **Offers**.
2) Tap **Add** (or the + / create button).
3) Fill in the offer details:
   - Name/label (optional but helpful for identifying it).
   - Price/amount: the M-PESA payment amount that should trigger this offer.
   - Bundle specifics (data/SMS/minutes) if applicable.
   - USSD string to dial (exact code as you would dial manually), and SIM slot if required.
4) Save. The offer now appears in the list and will be matched for incoming payments of that amount.

## Edit an Existing Offer (in-app)
1) Open **Offers** from Dashboard → “My tools”.
2) Tap the offer you want to edit.
3) Update fields (amount, USSD code, label, SIM slot, status).
4) Save. The updated offer will be used for future matches.

## Important Behaviors
- Matching: Incoming M-PESA SMS amounts are mapped to the nearest matching offer; paused/inactive offers are ignored.
- Pausing: If you suspect offer changes, mark offers as paused; the transaction flow will skip them.
- Advanced/queued USSD: Some flows need the app active and required permissions (SMS/phone/accessibility).

## Tips
- Keep USSD codes exact, including any required suffixes or commas for pauses if your flow needs them.
- If multiple SIMs are present, set the correct SIM slot to avoid dialing errors.
- If amounts aren’t matching, confirm the stored amount and active status of the offer.

## Where to Look in Code
- UI: [lib/screens/offers/offers.dart](../../lib/screens/offers/offers.dart) and [lib/screens/offers/edit_offer.dart](../../lib/screens/offers/edit_offer.dart)
- Matching/automation: check services handling M-PESA parsing and USSD dialing (e.g., `transaction_controller.dart`, `my_ussd_service.dart`).
