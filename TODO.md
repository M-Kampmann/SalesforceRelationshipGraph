# TODO

## UI Issues

- [ ] **Min Interactions control overlaps detail panel** — The `lightning-slider` had an internal minimum width that CSS couldn't override. Replaced with `lightning-input type="number"` but that's worse UX. Need a better approach — options: move to a popover/menu, put on its own row below filters, or use a custom range input without SLDS constraints.

## Known Limitations

- [ ] **Co-occurrence detection for Events** — Currently groups Events by Subject+StartDateTime to detect co-occurrence. This works for seed data (separate Event per contact) but may double-count if Shared Activities is enabled. Consider adding EventRelation as secondary source.
- [ ] **Email counting** — Requires `EmailMessage` and `EmailMessageRelation` objects which are only available with Email-to-Salesforce or Einstein Activity Capture enabled. Seed data doesn't include email records.
