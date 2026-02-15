# TODO

## UI Issues

- [ ] **Min Interactions control overlaps detail panel** — The `lightning-slider` had an internal minimum width that CSS couldn't override. Replaced with `lightning-input type="number"` but that's worse UX. Need a better approach — options: move to a popover/menu, put on its own row below filters, or use a custom range input without SLDS constraints.

## Known Limitations

- [ ] **Co-occurrence detection for Events** — Currently groups Events by Subject+StartDateTime to detect co-occurrence. This works for seed data (separate Event per contact) but may double-count if Shared Activities is enabled. Consider adding EventRelation as secondary source.
- [ ] **Email counting** — Requires `EmailMessage` and `EmailMessageRelation` objects which are only available with Email-to-Salesforce or Einstein Activity Capture enabled. Seed data doesn't include email records.

## Backlog

- [ ] **Additional LLM providers** — Add Claude API, OpenAI, etc. as classification providers. The `IClassificationProvider` interface and `ClassificationProviderFactory` registry are ready for extension.

---

## Production UAT — Einstein Classification Provider

Run these tests in a production-like org with Einstein/Agentforce enabled.

### Pre-requisites

- [ ] Einstein/Agentforce license active on the org
- [ ] Package deployed successfully
- [ ] Permission set `Relationship_Graph_Admin` assigned to test user
- [ ] Remote Site Setting created for org's My Domain URL

### Test 1: Einstein Availability Check

**Steps:**
1. Open Developer Console > Execute Anonymous
2. Run:
   ```apex
   EinsteinClassificationProvider p = new EinsteinClassificationProvider();
   System.debug('Available: ' + p.isAvailable());
   System.debug('Provider: ' + p.getProviderName());
   ```

**Expected:** `Available: true`, `Provider: EinsteinClassificationProvider`

**If false:** Check Remote Site Setting URL matches `URL.getOrgDomainUrl()`. Run:
```apex
System.debug(URL.getOrgDomainUrl().toExternalForm());
```

### Test 2: Factory Selects Einstein

**Steps:**
1. Verify config: Developer Console > Query Editor:
   ```sql
   SELECT Classification_Provider__c FROM Relationship_Graph_Config__mdt WHERE DeveloperName = 'Default'
   ```
2. Run:
   ```apex
   IClassificationProvider p = ClassificationProviderFactory.getProvider();
   System.debug('Active provider: ' + p.getProviderName());
   ```

**Expected:** `Active provider: EinsteinClassificationProvider`

### Test 3: End-to-End Classification via Refresh

**Steps:**
1. Navigate to an Account with 5+ Contacts that have Tasks/Events
2. Add the `relationshipGraph` component to the Account record page (if not already)
3. Click the **Refresh** button on the graph
4. Wait 5-10 seconds (classification runs async via Queueable)
5. Click Refresh again to pick up new classifications
6. Click on a Contact node to open the detail panel

**Expected:**
- Contact nodes show color-coded classifications (not all "Unknown")
- Detail panel shows `Provider: EinsteinClassificationProvider`
- Confidence scores vary between contacts (not all identical)

### Test 4: Classification Quality Spot-Check

**Steps:**
1. After Test 3, query classifications:
   ```sql
   SELECT Contact__r.Name, Contact__r.Title, Classification__c,
          Confidence_Score__c, Provider__c
   FROM Contact_Classification__c
   WHERE Account__c = '<account-id>'
   AND Provider__c = 'EinsteinClassificationProvider'
   ORDER BY Confidence_Score__c DESC
   ```
2. Verify classifications make sense:
   - CEO/CFO → Economic Buyer
   - CTO/VP Engineering → Technical Buyer
   - High-engagement contacts → Champion or Influencer
   - Low-engagement contacts → End User or Unknown

**Expected:** Classifications roughly align with contact titles and activity levels. Confidence scores range between 0.5-1.0.

### Test 5: User Override Persists Over Einstein

**Steps:**
1. Open the graph, click a Contact node
2. In the detail panel, change the classification dropdown to a different value
3. Click Refresh on the graph
4. Click the same Contact node again

**Expected:**
- Classification shows the user-overridden value (not Einstein's)
- `Is_User_Override__c = true` on that record
- Einstein does not overwrite user overrides (ClassificationQueueable filters `Is_User_Override__c = false`)

### Test 6: Fallback When Einstein Unavailable

**Steps:**
1. Temporarily change config: Setup > Custom Metadata Types > Relationship Graph Config > Default
2. Set `Classification_Provider__c` to `EinsteinClassificationProvider`
3. Delete the Remote Site Setting for your org domain
4. Run:
   ```apex
   IClassificationProvider p = ClassificationProviderFactory.getProvider();
   System.debug('Fallback provider: ' + p.getProviderName());
   ```
5. Re-create the Remote Site Setting after testing

**Expected:** `Fallback provider: HeuristicClassificationProvider` — factory falls back gracefully.

### Test 7: Bulk Classification (10+ Contacts)

**Steps:**
1. Pick an Account with 10-15 Contacts
2. Run:
   ```apex
   InteractionDataService svc = new InteractionDataService();
   List<Id> cIds = svc.getAccountContactIds('<account-id>');
   System.debug('Contact count: ' + cIds.size());
   System.enqueueJob(new ClassificationQueueable('<account-id>', cIds));
   ```
3. After 10-20 seconds, query results:
   ```sql
   SELECT COUNT() FROM Contact_Classification__c
   WHERE Account__c = '<account-id>'
   AND Provider__c = 'EinsteinClassificationProvider'
   ```

**Expected:** Count matches or is close to the number of contacts. All contacts classified without governor limit errors.
