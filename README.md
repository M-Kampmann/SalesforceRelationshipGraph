# Salesforce Relationship Graph

An interactive force-directed graph visualization for Salesforce that maps relationships between Contacts, Accounts, and Opportunities. Built as a Lightning Web Component with D3.js, it uses interaction data (emails, meetings, tasks) to compute relationship strengths and classify contact roles using a pluggable AI/heuristic engine.

## Architecture

```
LWC (D3.js Graph)
       |
RelationshipGraphController  (@AuraEnabled + Platform Cache)
       |
  +-----------+-----------------------+
  |           |                       |
GraphData  RelationshipStrength   Classification
Service    Calculator             Providers
  |           |                       |
  |     InteractionData          +----+----+
  |     Service                  |         |
  |                         Heuristic  Einstein
  |                         Provider   Provider
  +------ Custom Objects ------+
    Contact_Classification__c
    Relationship_Strength__c
    Relationship_Graph_Config__mdt
```

**Key patterns**: Strategy (classification providers), Factory (provider selection with fallback), Bulk SOQL (6 queries for interaction data), Platform Cache (graph data TTL), Queueable (async classification).

## Custom Objects

### Contact_Classification__c
Stores the role classification for a contact within an account context.

| Field | Type | Description |
|---|---|---|
| Contact__c | Lookup(Contact) | The classified contact |
| Account__c | Lookup(Account) | Account context |
| Classification__c | Picklist | Champion, Economic Buyer, Technical Buyer, Blocker, Influencer, End User, Detractor, Unknown |
| Confidence_Score__c | Number(4,3) | Classifier confidence (0.0-1.0) |
| Provider__c | Text(100) | Which provider generated this |
| Is_User_Override__c | Checkbox | Manual override flag |
| Last_Classified__c | DateTime | When last classified |

### Relationship_Strength__c
Pre-computed relationship strength between a contact and another record (Account, Contact, or Opportunity).

| Field | Type | Description |
|---|---|---|
| Source_Contact__c | Lookup(Contact) | Source contact |
| Target_Record_Id__c | Text(18) | Polymorphic target record ID |
| Target_Object_Type__c | Text(100) | Account, Contact, or Opportunity |
| Account__c | Lookup(Account) | Account context |
| Strength__c | Number(5,4) | Normalized score (0.0-1.0) |
| Interaction_Count__c | Number(8,0) | Total interactions |
| Co_Occurrence_Count__c | Number(8,0) | Shared email/meeting count |
| Last_Interaction_Date__c | DateTime | Most recent interaction |
| Last_Calculated__c | DateTime | Computation timestamp |

### Relationship_Graph_Config__mdt
Custom Metadata Type for system-wide configuration.

| Field | Default | Description |
|---|---|---|
| Classification_Provider__c | EinsteinClassificationProvider | Active classification backend |
| Activity_Threshold_Days__c | 90 | Activity lookback window |
| Min_Interactions__c | 3 | Minimum interactions to display |
| Time_Decay_Factor__c | 0.95 | Decay factor for stale relationships |
| Cache_TTL_Minutes__c | 60 | Platform cache TTL |

## Setup

### Prerequisites

- Salesforce CLI (`sf`)
- A Dev Hub org with scratch org creation enabled
- Node.js (for LWC Jest tests)

### Create Scratch Org and Deploy

```bash
# 1. Create scratch org
sf org create scratch \
  --definition-file config/project-scratch-def.json \
  --alias relgraph \
  --set-default \
  --duration-days 7 \
  --target-dev-hub <your-devhub-username>

# 2. Deploy source
sf project deploy start --source-dir force-app --target-org relgraph

# 3. Assign permission set (required for field-level security)
sf org assign permset --name Relationship_Graph_Admin --target-org relgraph

# 4. Seed sample data
sf apex run --file scripts/seed-data.apex --target-org relgraph

# 5. Open the org
sf org open --target-org relgraph
```

> **Important**: Step 3 is required. Custom fields deployed via metadata don't auto-grant field-level security. Without the permission set assignment, optional fields (Confidence_Score__c, Provider__c, etc.) won't be accessible in Apex or the UI.

### Permission Sets

| Permission Set | Purpose |
|---|---|
| Relationship_Graph_Admin | Full CRUD on custom objects, all field access. Assign to admins and users who can override classifications. |
| Relationship_Graph_User | Read-only access to custom objects and fields. Assign to standard users viewing the graph. |

## Testing

### Apex Tests

106 Apex tests run automatically during deployment with `--test-level RunLocalTests`:

```bash
sf project deploy start --source-dir force-app --target-org relgraph --test-level RunLocalTests
```

Test classes cover all services, providers, and the controller:
- `RelationshipGraphControllerTest` — Controller methods, cache, config, node details
- `GraphDataServiceTest` — Graph data building, filtering, edge generation, risk alerts
- `InteractionDataServiceTest` — Bulk data fetching, co-occurrence, sentiment
- `RelationshipStrengthCalculatorTest` — Strength scoring, time decay, persistence
- `HeuristicClassificationProviderTest` — Rule-based classification logic
- `EinsteinClassificationProviderTest` — Einstein API integration with HTTP mocks
- `ClassificationProviderFactoryTest` — Provider registry, fallback logic
- `ClassificationQueueableTest` — Async classification job
- `ClassificationResultTest` — Validation, valid classifications

### LWC Jest Tests

37 Jest tests for the LWC component:

```bash
npm install
npm run test:unit

# Watch mode
npm run test:unit:watch

# Coverage report
npm run test:unit:coverage
```

## Configuration

The graph behavior is controlled by the `Relationship_Graph_Config__mdt.Default` custom metadata record. Modify values in Setup > Custom Metadata Types > Relationship Graph Config.

To switch classification providers, update `Classification_Provider__c`:
- `HeuristicClassificationProvider` - Rule-based (title + interaction patterns + sentiment). Always available.
- `EinsteinClassificationProvider` - AI-powered via Einstein Models API. Requires Einstein setup (see below).

### Einstein Classification Provider Setup

The `EinsteinClassificationProvider` calls the Einstein Models API (`/services/data/v62.0/einstein/llm/prompt-completions`) to classify contacts using AI. It requires:

1. **Einstein/Agentforce license** enabled on the org
2. **Remote Site Setting** for self-callout — the provider makes an HTTP callout to its own org's REST API:
   - Go to Setup > Remote Site Settings > New
   - Name: `SelfOrg` (or any descriptive name)
   - URL: Your org's My Domain URL (e.g. `https://yourorg.my.salesforce.com`)
   - Active: checked
3. **Verify**: Open Developer Console > Execute Anonymous:
   ```apex
   EinsteinClassificationProvider p = new EinsteinClassificationProvider();
   System.debug('Available: ' + p.isAvailable());
   ```
   Should print `Available: true`. If false, check Remote Site Setting and Einstein license.

When Einstein is unavailable, the factory automatically falls back to `HeuristicClassificationProvider`. No user action needed — the fallback is transparent.

## LWC Component Usage

Add `relationshipGraph` to any Account record page, app page, or home page via Lightning App Builder.

**Component properties**:
- **Show All Contacts** (`showAllContacts`) - Include passive/low-interaction contacts (default: off)
- **Min Interactions** (`defaultMinInteractions`) - Minimum interaction count to display a contact (default: 3)

**Interaction weights** used for strength calculation:

| Interaction Type | Weight |
|---|---|
| Email Sent | 1.0 |
| Email Received | 1.5 |
| Meeting | 3.0 |
| Task | 1.0 |
| Opportunity Role | 5.0 |
| Co-occurrence | 0.5 |

## Seed Data

The `scripts/seed-data.apex` script creates demo data for testing:

| Object | Count |
|---|---|
| Accounts | 3 (Acme Corporation, Global Industries, Pinnacle Solutions) |
| Contacts | 19 (with realistic titles and varied engagement levels) |
| Opportunities | 4 |
| Tasks | ~80 |
| Events | 16 |
| Contact Classifications | 19 |
| Relationship Strengths | 25 |

## License

Private
