/**
 * Main Apex controller for the Relationship Graph LWC.
 * Exposes @AuraEnabled methods for graph data retrieval, classification, and configuration.
 * Uses Platform Cache for performance.
 */
public with sharing class RelationshipGraphController {

    private static final String CACHE_PARTITION = 'local.RelationshipGraph';
    private static Relationship_Graph_Config__mdt cachedConfig;
    private static Boolean configLoaded = false;

    // ─── Graph Data ─────────────────────────────────────────────────

    /**
     * Get graph data for an account.
     * Checks Platform Cache first, falls back to fresh computation.
     */
    @AuraEnabled(cacheable=true)
    public static GraphDataService.GraphData getGraphData(
        Id accountId,
        Boolean hidePassive,
        Integer minInteractions,
        Integer thresholdDays
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        // Try cache first
        String cacheKey = buildCacheKey(accountId, hidePassive, minInteractions);
        GraphDataService.GraphData cached = getCachedGraphData(cacheKey);
        if (cached != null) {
            return cached;
        }

        // Build fresh
        GraphDataService service = new GraphDataService();
        GraphDataService.GraphData graphData = service.buildGraphData(
            accountId, hidePassive, minInteractions, thresholdDays
        );

        // Cache the result
        cacheGraphData(cacheKey, graphData);

        return graphData;
    }

    /**
     * Force refresh graph data (bypasses cache).
     * Also triggers re-computation of relationship strengths and classifications.
     */
    @AuraEnabled
    public static GraphDataService.GraphData refreshGraphData(
        Id accountId,
        Boolean hidePassive,
        Integer minInteractions,
        Integer thresholdDays
    ) {
        if (accountId == null) {
            throw new AuraHandledException('Account ID is required');
        }

        // Recompute interaction data and strengths
        InteractionDataService dataService = new InteractionDataService();
        List<Id> contactIds = dataService.getAccountContactIds(accountId);

        InteractionDataService.InteractionBundle bundle =
            dataService.fetchInteractionData(accountId, contactIds);

        // Get config
        Relationship_Graph_Config__mdt config = getConfig();
        Decimal decayFactor = config != null ? config.Time_Decay_Factor__c : 0.95;

        // Recalculate strengths
        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();
        calculator.calculateAndPersist(accountId, contactIds, bundle, decayFactor);

        // Trigger async classification
        System.enqueueJob(new ClassificationQueueable(accountId, contactIds));

        // Build fresh graph data
        GraphDataService service = new GraphDataService();
        GraphDataService.GraphData graphData = service.buildGraphData(
            accountId, hidePassive, minInteractions, thresholdDays
        );

        // Update cache
        String cacheKey = buildCacheKey(accountId, hidePassive, minInteractions);
        cacheGraphData(cacheKey, graphData);

        return graphData;
    }

    // ─── Node Details ───────────────────────────────────────────────

    /**
     * Get detailed information for a specific node (Contact, Account, or Opportunity).
     */
    @AuraEnabled(cacheable=true)
    public static NodeDetail getNodeDetail(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Record ID is required');
        }

        String objectType = recordId.getSObjectType().getDescribe().getName();
        NodeDetail detail = new NodeDetail();
        detail.recordId = String.valueOf(recordId);
        detail.objectType = objectType;

        if (objectType == 'Contact') {
            List<Contact> contacts = [
                SELECT Id, Name, Title, Email, Phone, AccountId, Account.Name,
                       MailingCity, MailingState
                FROM Contact
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (contacts.isEmpty()) {
                throw new AuraHandledException('Contact not found or not accessible');
            }
            Contact c = contacts[0];
            detail.name = c.Name;
            detail.title = c.Title;
            detail.email = c.Email;
            detail.phone = c.Phone;
            detail.accountName = c.Account?.Name;

            // Get classification
            List<Contact_Classification__c> classifications = [
                SELECT Classification__c, Confidence_Score__c, Provider__c, Is_User_Override__c
                FROM Contact_Classification__c
                WHERE Contact__c = :recordId
                WITH SECURITY_ENFORCED
                ORDER BY Is_User_Override__c DESC, Last_Classified__c DESC
                LIMIT 1
            ];
            if (!classifications.isEmpty()) {
                detail.classification = classifications[0].Classification__c;
                detail.confidence = classifications[0].Confidence_Score__c;
                detail.classificationProvider = classifications[0].Provider__c;
                detail.isUserOverride = classifications[0].Is_User_Override__c;
            }

            // Get recent interactions count
            detail.recentInteractions = getRecentInteractionCount(recordId);

        } else if (objectType == 'Account') {
            List<Account> accounts = [
                SELECT Id, Name, Industry, Type, Website, NumberOfEmployees
                FROM Account
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (accounts.isEmpty()) {
                throw new AuraHandledException('Account not found or not accessible');
            }
            Account a = accounts[0];
            detail.name = a.Name;
            detail.industry = a.Industry;
            detail.accountType = a.Type;
            detail.website = a.Website;

        } else if (objectType == 'Opportunity') {
            List<Opportunity> opps = [
                SELECT Id, Name, StageName, Amount, CloseDate, Probability
                FROM Opportunity
                WHERE Id = :recordId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (opps.isEmpty()) {
                throw new AuraHandledException('Opportunity not found or not accessible');
            }
            Opportunity o = opps[0];
            detail.name = o.Name;
            detail.stage = o.StageName;
            detail.amount = o.Amount;
            detail.closeDate = o.CloseDate;
            detail.probability = o.Probability;
        }

        return detail;
    }

    // ─── Classification Override ─────────────────────────────────────

    /**
     * Allow user to override a contact's classification.
     */
    @AuraEnabled
    public static void overrideClassification(
        Id contactId, Id accountId, String classification
    ) {
        if (!ClassificationResult.VALID_CLASSIFICATIONS.contains(classification)) {
            throw new AuraHandledException('Invalid classification: ' + classification);
        }

        // Check for existing user override
        List<Contact_Classification__c> existing = [
            SELECT Id
            FROM Contact_Classification__c
            WHERE Contact__c = :contactId
            AND Account__c = :accountId
            AND Is_User_Override__c = true
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Contact_Classification__c cc;
        if (!existing.isEmpty()) {
            cc = existing[0];
        } else {
            cc = new Contact_Classification__c(
                Contact__c = contactId,
                Account__c = accountId
            );
        }

        cc.Classification__c = classification;
        cc.Confidence_Score__c = 1.0;
        cc.Provider__c = 'UserOverride';
        cc.Is_User_Override__c = true;
        cc.Last_Classified__c = Datetime.now();

        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPSERTABLE, new List<Contact_Classification__c>{ cc }
        );
        upsert decision.getRecords();
    }

    // ─── Configuration ──────────────────────────────────────────────

    /**
     * Get current graph configuration.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getGraphConfig() {
        Relationship_Graph_Config__mdt config = getConfig();
        Map<String, Object> result = new Map<String, Object>();

        if (config != null) {
            result.put('classificationProvider', config.Classification_Provider__c);
            result.put('activityThresholdDays', config.Activity_Threshold_Days__c);
            result.put('minInteractions', config.Min_Interactions__c);
            result.put('timeDecayFactor', config.Time_Decay_Factor__c);
            result.put('cacheTTLMinutes', config.Cache_TTL_Minutes__c);
        } else {
            // Defaults
            result.put('classificationProvider', 'AgentforceClassificationProvider');
            result.put('activityThresholdDays', 90);
            result.put('minInteractions', 3);
            result.put('timeDecayFactor', 0.95);
            result.put('cacheTTLMinutes', 60);
        }

        // Add available classifications for UI
        result.put('classifications', new List<String>(ClassificationResult.VALID_CLASSIFICATIONS));

        return result;
    }

    // ─── Private Helpers ────────────────────────────────────────────

    private static Relationship_Graph_Config__mdt getConfig() {
        if (!configLoaded) {
            List<Relationship_Graph_Config__mdt> configs = [
                SELECT Classification_Provider__c, Activity_Threshold_Days__c,
                       Min_Interactions__c, Time_Decay_Factor__c, Cache_TTL_Minutes__c
                FROM Relationship_Graph_Config__mdt
                WHERE DeveloperName = 'Default'
                LIMIT 1
            ];
            cachedConfig = configs.isEmpty() ? null : configs[0];
            configLoaded = true;
        }
        return cachedConfig;
    }

    private static Integer getRecentInteractionCount(Id contactId) {
        Integer count = 0;
        Date thirtyDaysAgo = Date.today().addDays(-30);

        count += [
            SELECT COUNT() FROM Task
            WHERE WhoId = :contactId AND CreatedDate >= :thirtyDaysAgo
            WITH SECURITY_ENFORCED
        ];

        count += [
            SELECT COUNT() FROM Event
            WHERE WhoId = :contactId AND CreatedDate >= :thirtyDaysAgo
            WITH SECURITY_ENFORCED
        ];

        return count;
    }

    private static String buildCacheKey(Id accountId, Boolean hidePassive, Integer minInteractions) {
        return 'graph_' + String.valueOf(accountId).left(15)
            + '_' + (hidePassive ? '1' : '0')
            + '_' + minInteractions;
    }

    private static GraphDataService.GraphData getCachedGraphData(String cacheKey) {
        try {
            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            Object cached = partition.get(cacheKey);
            if (cached != null) {
                return (GraphDataService.GraphData) cached;
            }
        } catch (Exception e) {
            // Platform Cache may not be configured — that's OK
            System.debug(LoggingLevel.WARN, 'Cache read failed: ' + e.getMessage());
        }
        return null;
    }

    private static void cacheGraphData(String cacheKey, GraphDataService.GraphData data) {
        try {
            Relationship_Graph_Config__mdt config = getConfig();
            Integer ttlSeconds = config != null
                ? Integer.valueOf(config.Cache_TTL_Minutes__c) * 60
                : 3600;

            Cache.OrgPartition partition = Cache.Org.getPartition(CACHE_PARTITION);
            partition.put(cacheKey, data, ttlSeconds);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Cache write failed: ' + e.getMessage());
        }
    }

    // ─── Inner Classes ──────────────────────────────────────────────

    public class NodeDetail {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String objectType { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String phone { get; set; }
        @AuraEnabled public String accountName { get; set; }
        @AuraEnabled public String classification { get; set; }
        @AuraEnabled public Decimal confidence { get; set; }
        @AuraEnabled public String classificationProvider { get; set; }
        @AuraEnabled public Boolean isUserOverride { get; set; }
        @AuraEnabled public Integer recentInteractions { get; set; }
        @AuraEnabled public String industry { get; set; }
        @AuraEnabled public String accountType { get; set; }
        @AuraEnabled public String website { get; set; }
        @AuraEnabled public String stage { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        @AuraEnabled public Date closeDate { get; set; }
        @AuraEnabled public Decimal probability { get; set; }
    }
}
