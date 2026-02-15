# TODO

## UI Issues

- [ ] **Min Interactions control overlaps detail panel** — The `lightning-slider` had an internal minimum width that CSS couldn't override. Replaced with `lightning-input type="number"` but that's worse UX. Need a better approach — options: move to a popover/menu, put on its own row below filters, or use a custom range input without SLDS constraints.

## Known Limitations

- [ ] **Co-occurrence detection for Events** — Currently groups Events by Subject+StartDateTime to detect co-occurrence. This works for seed data (separate Event per contact) but may double-count if Shared Activities is enabled. Consider adding EventRelation as secondary source.
- [ ] **Email counting** — Requires `EmailMessage` and `EmailMessageRelation` objects which are only available with Email-to-Salesforce or Einstein Activity Capture enabled. Seed data doesn't include email records.

## Backlog

- [ ] **Additional LLM providers** — Add Claude API, OpenAI, etc. as classification providers. The `IClassificationProvider` interface and `ClassificationProviderFactory` registry are ready for extension.
- [ ] **Configurable risk thresholds** — Stale champion threshold (currently 30 days), active blocker threshold (currently 5 interactions), weak buyer threshold (currently 0.3 strength) are hardcoded in `GraphDataService.detectRisks()`. Consider adding to `Relationship_Graph_Config__mdt`.
- [ ] **Risk alert history/trending** — Track how risk alerts change over time. Currently computed fresh on each graph load with no persistence.
- [ ] **Multi-account view** — Cross-account relationship map showing contacts bridging multiple deals.
- [ ] **Timeline/history mode** — Animate relationship evolution over time using `Last_Interaction_Date__c` and `Last_Classified__c`.
- [ ] **Contact-to-Contact strength edges** — Co-occurrence data exists in `Relationship_Strength__c` (Target_Object_Type = Contact) but graph only partially renders these. Full internal alliance/silo visualization.
- [ ] **Influence path finder** — "How do I reach the Economic Buyer?" — shortest path through Champions and Influencers.
- [ ] **Strength factor analytics** — Dashboard showing which factors contribute most across accounts. Aggregate `Strength_Breakdown__c` JSON data.
- [ ] **Record_Count factor examples** — Provide example `Strength_Factor__mdt` records for common objects (Cases, Projects, Campaigns) in documentation or as unmanaged package add-on.

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

---

## Production UAT — Relationship Risk Alerts

Run these after deploying the risk alerts feature. No special prerequisites beyond the base setup.

### Test 8: Risk Alerts Appear on Graph Load

**Steps:**
1. Navigate to an Account with contacts that have classifications and interaction data
2. Open the Relationship Graph component
3. Look at the stats bar (footer)

**Expected:**
- A risk alert button appears (e.g. "3 Risks") if any risks are detected
- Button is red (`destructive` variant) if any high-severity alerts exist
- Button is neutral if only medium-severity alerts

### Test 9: Risk Panel Opens and Shows Alerts

**Steps:**
1. Click the risk alert button in the stats bar
2. Review the risk panel that appears on the left side

**Expected:**
- Panel shows all detected risks with severity indicators
- High-severity alerts have a red left border
- Medium-severity alerts have an orange left border
- Each alert shows a risk type label and descriptive message
- Alerts with contact names show the contact's name

### Test 10: Click Risk Alert to Navigate to Contact

**Steps:**
1. Open the risk panel
2. Click on an alert that references a specific contact (e.g. "Stale Champion" or "Active Blocker")

**Expected:**
- The canvas centers on the referenced contact node
- The detail panel opens showing that contact's information
- The contact node has a dashed red or orange ring around it

### Test 11: Risk Ring Indicators on Canvas Nodes

**Steps:**
1. Load the graph for an account with known risks
2. Look at contact nodes on the canvas

**Expected:**
- Contacts with high-severity risks have a dashed red ring around them
- Contacts with medium-severity risks have a dashed orange ring
- Contacts with no risks have no extra ring (just the normal white border)
- The ring is visible at different zoom levels

### Test 12: Verify Each Risk Type Fires Correctly

**Steps:**
1. Query your account data and verify the following scenarios. Use Developer Console Execute Anonymous to check:
   ```apex
   GraphDataService svc = new GraphDataService();
   GraphDataService.GraphData graph = svc.buildGraphData('<account-id>', false, 0, 90);
   for (GraphDataService.RiskAlert alert : graph.riskAlerts) {
       System.debug(alert.severity + ' | ' + alert.riskType + ' | ' + alert.message);
   }
   ```

**Expected risk types and when they fire:**

| Risk Type | Fires When |
|---|---|
| `stale_champion` | Champion with `Last_Interaction_Date__c` > 30 days ago |
| `no_economic_buyer` | No contact classified as "Economic Buyer" |
| `active_blocker` | Blocker or Detractor with > 5 interactions |
| `weak_key_buyer` | Economic/Technical Buyer with strength < 0.3 |
| `single_threaded` | Only 1 Champion, or only 1 Economic Buyer |
| `ghost_champion` | Champion with confidence < 50% |

### Test 13: No False Positives on Healthy Account

**Steps:**
1. Find or create an account with:
   - 3+ Champions (recent activity, high confidence)
   - 1+ Economic Buyer (strong relationship)
   - No Blockers or Detractors
2. Load the graph

**Expected:**
- No risk alert button in stats bar (or only low-count medium alerts like single-threaded EB)
- No red rings on any nodes

### Test 14: Risk Alerts Refresh After Data Change

**Steps:**
1. Load graph, note the risk alerts
2. Override a contact's classification (e.g. change "Unknown" to "Economic Buyer")
3. Click Refresh

**Expected:**
- Risk alert count may change (e.g. "No Economic Buyer" alert disappears)
- Risk panel updates to reflect new state

---

## Production UAT — Configurable Strength Factors

Run these after deploying the configurable strength factors feature.

### Pre-requisites

- [ ] Package deployed successfully (includes `Strength_Factor__mdt` and 6 default records)
- [ ] Permission set `Relationship_Graph_Admin` assigned to test user
- [ ] `Strength_Breakdown__c` field visible on `Relationship_Strength__c`

### Test 15: Default Factors Match Previous Behavior

**Steps:**
1. Navigate to an Account with existing strength data
2. Click Refresh on the Relationship Graph
3. Compare scores before and after refresh

**Expected:**
- Scores are identical or negligibly different (6 default CMT records match original hardcoded weights)
- No regression in score calculation

### Test 16: Score Breakdown Visible in Detail Panel

**Steps:**
1. Load the graph for an Account with interaction data
2. Click on a Contact node with a non-zero strength
3. Look for the "Score Breakdown" section in the detail panel

**Expected:**
- Factor breakdown bars appear below "Connection Insight"
- Each factor shows: name, optional category label, horizontal bar, numeric contribution
- Factors are sorted by contribution (highest first)
- Only non-zero factors appear

### Test 17: Change Factor Weight

**Steps:**
1. Go to Setup > Custom Metadata Types > Strength Factor > Manage Records
2. Edit `Email_Sent` — change Weight from `1.0` to `5.0`
3. Return to the Account and click Refresh
4. Click a Contact with email interactions

**Expected:**
- Email Sent contribution in the breakdown is noticeably higher
- Overall strength score changes for contacts with email activity
- Reset weight to `1.0` after testing

### Test 18: Deactivate a Factor

**Steps:**
1. Go to Setup > Custom Metadata Types > Strength Factor > Manage Records
2. Edit `Co_Occurrence` — uncheck `Is_Active__c`
3. Refresh the graph
4. Click a Contact that had co-occurrence data

**Expected:**
- Co-Occurrence no longer appears in the Score Breakdown
- Overall strength score may decrease slightly
- Re-activate after testing

### Test 19: Add a Contact_Field Factor (e.g. CSAT/NPS)

**Steps:**
1. Ensure a numeric field exists on Contact (e.g. `CSAT_Score__c` or use a standard numeric field like `Birthdate` won't work — must be Number/Currency/Percent)
2. Go to Setup > Custom Metadata Types > Strength Factor > New
3. Configure:
   - Label: `CSAT Score`
   - Source Type: `Contact_Field`
   - Source Value: `CSAT_Score__c`
   - Weight: `2.0`
   - Max Value: `100` (normalizes 0-100 scale to 0-1)
   - Category: `Satisfaction`
   - Is Active: checked
4. Refresh the graph

**Expected:**
- Contacts with non-null CSAT values show "CSAT Score" in their Score Breakdown
- Category shows "Satisfaction" under the factor name
- Bar width reflects the normalized score (e.g. CSAT=80 with Max=100 → 0.8 × 2.0 = 1.6 contribution)
- Contacts without CSAT data show no CSAT factor in breakdown

### Test 20: Add a Record_Count Factor (e.g. Projects)

**Steps:**
1. Ensure a custom object with a Contact lookup exists (e.g. `Project__c.Contact__c`)
2. Go to Setup > Custom Metadata Types > Strength Factor > New
3. Configure:
   - Label: `Projects Conducted`
   - Source Type: `Record_Count`
   - Source Value: `Project__c.Contact__c`
   - Weight: `3.0`
   - Max Value: `10`
   - Category: `Product Usage`
   - Is Active: checked
4. Refresh the graph

**Expected:**
- Contacts with related Project records show "Projects Conducted" in breakdown
- Count is normalized by Max Value (e.g. 5 projects / 10 max = 0.5 × 3.0 = 1.5 contribution)

### Test 21: Invalid Factor Configuration Handled Gracefully

**Steps:**
1. Create a `Contact_Field` factor with Source Value `Nonexistent_Field__c`
2. Create a `Record_Count` factor with Source Value `Nonexistent_Object__c.Contact__c`
3. Refresh the graph

**Expected:**
- Graph loads without errors
- Invalid factors are silently skipped (no crash, no error toast)
- Valid factors still appear in the breakdown
- Clean up invalid records after testing

### Test 22: Max Value Normalization Caps at 1.0

**Steps:**
1. Create a `Contact_Field` factor with Weight `2.0` and Max Value `50`
2. Ensure a Contact has the field value set to `100` (exceeds max)
3. Refresh the graph

**Expected:**
- Factor's raw value in breakdown shows `100`
- Contribution is capped: `min(100/50, 1.0) × 2.0 = 2.0` (not 4.0)

### Test 23: Strength Reason Includes Custom Factors

**Steps:**
1. With custom factors active, click a Contact node
2. Check the "Connection Insight" text

**Expected:**
- Built-in interactions listed first (emails, meetings, tasks, etc.)
- Custom factors appended with name and raw value (e.g. "CSAT Score: 85.0 (Satisfaction)")

### Test 24: Hardcoded Fallback When No CMT Records

**Steps:**
1. Deactivate ALL 6 default Strength Factor records (uncheck Is_Active on each)
2. Refresh the graph

**Expected:**
- Graph still loads with scores calculated using hardcoded fallback weights
- Scores match original behavior (Email Sent=1.0, Email Received=1.5, Meeting=3.0, etc.)
- Re-activate all records after testing
