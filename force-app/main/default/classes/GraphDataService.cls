/**
 * Builds the graph data model (nodes + edges) for the LWC visualization.
 * Reads pre-computed relationship strengths and classifications.
 * Supports filtering by activity threshold (hide passive contacts).
 */
public with sharing class GraphDataService {

    /**
     * Build the complete graph data for an account.
     * @param accountId The account to build the graph for
     * @param hidePassive If true, exclude contacts below the activity threshold
     * @param minInteractions Minimum interactions required (0 = show all)
     * @param thresholdDays Only count interactions within this many days
     * @return GraphData containing nodes and edges
     */
    public GraphData buildGraphData(
        Id accountId,
        Boolean hidePassive,
        Integer minInteractions,
        Integer thresholdDays
    ) {
        return buildGraphData(accountId, hidePassive, minInteractions, thresholdDays, null);
    }

    public GraphData buildGraphData(
        Id accountId,
        Boolean hidePassive,
        Integer minInteractions,
        Integer thresholdDays,
        InteractionDataService.InteractionBundle externalBundle
    ) {
        return buildGraphData(accountId, hidePassive, minInteractions, thresholdDays, externalBundle, false, null);
    }

    public GraphData buildGraphData(
        Id accountId,
        Boolean hidePassive,
        Integer minInteractions,
        Integer thresholdDays,
        InteractionDataService.InteractionBundle externalBundle,
        Boolean showHierarchy,
        Relationship_Graph_Config__mdt config
    ) {
        GraphData graph = new GraphData();

        // 1. Get account info
        Account acct = [
            SELECT Id, Name, Industry, Type
            FROM Account
            WHERE Id = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        // Add account as central node
        graph.nodes.add(new GraphNode(
            acct.Id, acct.Name, 'Account', null, null, 0, 0
        ));

        // 2. Get contacts and their classifications
        // Use dynamic SOQL when moved-contact fields are configured
        List<Contact> contacts = queryContacts(accountId, config);

        if (contacts.size() > 500) {
            graph.isTruncated = true;
            graph.totalContactCount = contacts.size(); // At least 501
            contacts.remove(500); // Trim back to 500
        } else {
            graph.totalContactCount = contacts.size();
        }

        Map<Id, Contact_Classification__c> classifications = getClassifications(
            accountId, new List<Contact>(contacts)
        );

        // 3. Get relationship strengths
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }

        Map<Id, Relationship_Strength__c> strengths = getStrengths(accountId, contactIds, thresholdDays);

        // 4. Build contact nodes (with optional passive filtering)
        Set<Id> includedContactIds = new Set<Id>();

        for (Contact c : contacts) {
            Relationship_Strength__c rs = strengths.get(c.Id);
            Integer interactionCount = rs != null ? Integer.valueOf(rs.Interaction_Count__c) : 0;

            // Apply passive filter
            if (hidePassive && interactionCount < minInteractions) {
                continue;
            }

            Contact_Classification__c cc = classifications.get(c.Id);
            String classification = cc != null ? cc.Classification__c : 'Unknown';
            Decimal confidence = cc != null ? cc.Confidence_Score__c : 0.0;
            Integer coOccurrenceCount = rs != null ? Integer.valueOf(rs.Co_Occurrence_Count__c) : 0;

            graph.nodes.add(new GraphNode(
                c.Id, c.Name, 'Contact', classification, c.Title,
                interactionCount, coOccurrenceCount
            ));
            GraphNode node = graph.nodes[graph.nodes.size() - 1];
            node.confidence = confidence;
            node.email = c.Email;

            // Populate moved-contact fields from dynamic query
            populateMovedFields(node, c, config);

            if (rs != null) {
                if (rs.Strength_Reason__c != null) {
                    node.strengthReason = rs.Strength_Reason__c;
                }
                node.lastInteractionDate = rs.Last_Interaction_Date__c;
                node.strength = rs.Strength__c;
                if (String.isNotBlank(rs.Strength_Breakdown__c)) {
                    try {
                        node.strengthFactors = (List<RelationshipStrengthCalculator.FactorBreakdown>)
                            JSON.deserialize(rs.Strength_Breakdown__c,
                                List<RelationshipStrengthCalculator.FactorBreakdown>.class);
                    } catch (Exception e) {
                        // Invalid JSON — skip breakdown
                    }
                }
            }

            includedContactIds.add(c.Id);
        }

        // 4.5 Resolve previousCompany names to Account IDs
        resolveMovedCompanyIds(graph);

        // 5. Build contact-to-account edges
        for (Id contactId : includedContactIds) {
            Relationship_Strength__c rs = strengths.get(contactId);
            Decimal strength = rs != null ? rs.Strength__c : 0.1;
            Integer interactions = rs != null ? Integer.valueOf(rs.Interaction_Count__c) : 0;

            graph.edges.add(new GraphEdge(
                contactId, accountId, strength, interactions, 'account_relationship'
            ));
        }

        // 6. Build contact-to-contact co-occurrence edges
        List<Relationship_Strength__c> coOccEdges = [
            SELECT Source_Contact__c, Target_Record_Id__c, Strength__c, Co_Occurrence_Count__c
            FROM Relationship_Strength__c
            WHERE Account__c = :accountId
            AND Target_Object_Type__c = 'Contact'
            AND Source_Contact__c IN :includedContactIds
            WITH SECURITY_ENFORCED
            LIMIT 2000
        ];

        for (Relationship_Strength__c rs : coOccEdges) {
            Id targetId;
            try {
                targetId = Id.valueOf(rs.Target_Record_Id__c);
            } catch (Exception e) {
                continue;
            }

            if (!includedContactIds.contains(targetId)) continue;

            graph.edges.add(new GraphEdge(
                rs.Source_Contact__c, targetId,
                rs.Strength__c,
                Integer.valueOf(rs.Co_Occurrence_Count__c),
                'co_occurrence'
            ));
        }

        // 7. Add opportunities as nodes
        addOpportunityNodes(accountId, includedContactIds, graph);

        // 7.5 Add external contact nodes if bundle provided
        if (externalBundle != null && !externalBundle.externalContactSummaries.isEmpty()) {
            addExternalContactNodes(externalBundle, includedContactIds, graph);
        }

        // 7.6 Add account hierarchy if enabled
        if (showHierarchy == true) {
            addAccountHierarchy(accountId, graph, config);
        }

        // 8. Detect relationship risks
        detectRisks(graph);

        return graph;
    }

    private Map<Id, Contact_Classification__c> getClassifications(
        Id accountId, List<Contact> contacts
    ) {
        Map<Id, Contact_Classification__c> result = new Map<Id, Contact_Classification__c>();
        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }

        for (Contact_Classification__c cc : [
            SELECT Contact__c, Classification__c, Confidence_Score__c, Provider__c, Is_User_Override__c
            FROM Contact_Classification__c
            WHERE Account__c = :accountId
            AND Contact__c IN :contactIds
            WITH SECURITY_ENFORCED
            ORDER BY Is_User_Override__c DESC, Last_Classified__c DESC
        ]) {
            // User overrides take priority (they're ordered first)
            if (!result.containsKey(cc.Contact__c)) {
                result.put(cc.Contact__c, cc);
            }
        }

        return result;
    }

    private Map<Id, Relationship_Strength__c> getStrengths(
        Id accountId, Set<Id> contactIds, Integer thresholdDays
    ) {
        Map<Id, Relationship_Strength__c> result = new Map<Id, Relationship_Strength__c>();
        Date cutoffDate = thresholdDays != null && thresholdDays > 0
            ? Date.today().addDays(-thresholdDays) : null;

        for (Relationship_Strength__c rs : [
            SELECT Source_Contact__c, Strength__c, Interaction_Count__c,
                   Co_Occurrence_Count__c, Last_Interaction_Date__c, Strength_Reason__c,
                   Strength_Breakdown__c
            FROM Relationship_Strength__c
            WHERE Account__c = :accountId
            AND Source_Contact__c IN :contactIds
            AND Target_Object_Type__c = 'Account'
            WITH SECURITY_ENFORCED
        ]) {
            // Filter by threshold days if configured
            if (cutoffDate != null
                && rs.Last_Interaction_Date__c != null
                && rs.Last_Interaction_Date__c < cutoffDate) {
                continue;
            }
            result.put(rs.Source_Contact__c, rs);
        }

        return result;
    }

    private void addOpportunityNodes(
        Id accountId, Set<Id> includedContactIds, GraphData graph
    ) {
        // Get opportunities for this account
        Map<Id, Opportunity> opps = new Map<Id, Opportunity>([
            SELECT Id, Name, StageName, Amount, CloseDate
            FROM Opportunity
            WHERE AccountId = :accountId
            AND IsClosed = false
            WITH SECURITY_ENFORCED
            LIMIT 20
        ]);

        if (opps.isEmpty()) return;

        // Get contact roles to create edges
        List<OpportunityContactRole> roles = [
            SELECT ContactId, OpportunityId, Role
            FROM OpportunityContactRole
            WHERE OpportunityId IN :opps.keySet()
            AND ContactId IN :includedContactIds
            WITH SECURITY_ENFORCED
        ];

        // Only add opportunities that have connected contacts
        Set<Id> connectedOppIds = new Set<Id>();
        for (OpportunityContactRole ocr : roles) {
            connectedOppIds.add(ocr.OpportunityId);
        }

        for (Id oppId : connectedOppIds) {
            Opportunity opp = opps.get(oppId);
            GraphNode node = new GraphNode(
                opp.Id, opp.Name, 'Opportunity', opp.StageName, null, 0, 0
            );
            node.amount = opp.Amount;
            node.closeDate = opp.CloseDate;
            graph.nodes.add(node);
        }

        // Add edges
        for (OpportunityContactRole ocr : roles) {
            if (!connectedOppIds.contains(ocr.OpportunityId)) continue;

            graph.edges.add(new GraphEdge(
                ocr.ContactId, ocr.OpportunityId, 0.5, 1, 'opportunity_role'
            ));
            graph.edges[graph.edges.size() - 1].label = ocr.Role;
        }
    }

    private void addExternalContactNodes(
        InteractionDataService.InteractionBundle bundle,
        Set<Id> includedContactIds,
        GraphData graph
    ) {
        // Filter to hydrated externals only
        List<InteractionDataService.ExternalContactSummary> hydrated =
            new List<InteractionDataService.ExternalContactSummary>();
        for (InteractionDataService.ExternalContactSummary ext : bundle.externalContactSummaries.values()) {
            if (String.isNotBlank(ext.contactName)) {
                hydrated.add(ext);
            }
        }

        // Sort by total shared interactions descending
        hydrated.sort();

        // Cap at 50
        Integer cap = Math.min(hydrated.size(), 50);

        for (Integer i = 0; i < cap; i++) {
            InteractionDataService.ExternalContactSummary ext = hydrated[i];
            Integer totalShared = ext.getTotalSharedInteractions();

            GraphNode node = new GraphNode(
                ext.contactId, ext.contactName, 'External_Contact',
                null, ext.contactTitle, totalShared, 0
            );
            node.email = ext.contactEmail;
            node.accountName = ext.accountName;
            node.accountId = ext.accountId != null ? String.valueOf(ext.accountId) : null;
            graph.nodes.add(node);

            // Add edges from external to each co-occurring internal contact
            for (Id internalId : ext.coOccurringInternalContactIds) {
                if (!includedContactIds.contains(internalId)) continue;

                graph.edges.add(new GraphEdge(
                    ext.contactId, internalId,
                    Math.min(totalShared / 20.0, 1.0),
                    totalShared,
                    'cross_account'
                ));
            }
        }
    }

    // ─── Contact Query with Dynamic Moved Fields ───────────────────

    @TestVisible
    private List<Contact> queryContacts(Id accountId, Relationship_Graph_Config__mdt config) {
        // Build dynamic SOQL to include configured moved fields
        String baseFields = 'Id, Name, Title, Email, AccountId';
        Set<String> extraFields = new Set<String>();

        if (config != null) {
            if (String.isNotBlank(config.Contact_Moved_Flag_Field__c)) {
                extraFields.add(config.Contact_Moved_Flag_Field__c.trim());
            }
            if (String.isNotBlank(config.Contact_Previous_Company_Field__c)) {
                extraFields.add(config.Contact_Previous_Company_Field__c.trim());
            }
            if (String.isNotBlank(config.Contact_Moved_Info_Field__c)) {
                extraFields.add(config.Contact_Moved_Info_Field__c.trim());
            }
        }

        // Try dynamic query with extra fields — use stripInaccessible so
        // individual FLS failures don't kill the whole query
        if (!extraFields.isEmpty()) {
            String fieldList = baseFields + ', ' + String.join(new List<String>(extraFields), ', ');
            String soql = 'SELECT ' + fieldList
                + ' FROM Contact WHERE AccountId = :accountId'
                + ' LIMIT 501';
            try {
                List<Contact> raw = Database.query(soql);
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.READABLE, raw
                );
                // Log any stripped fields
                Map<String, Set<String>> removed = decision.getRemovedFields();
                if (removed.containsKey('Contact')) {
                    for (String field : removed.get('Contact')) {
                        System.debug(LoggingLevel.WARN, 'FLS stripped field: ' + field);
                    }
                }
                return (List<Contact>) decision.getRecords();
            } catch (Exception e) {
                // Field doesn't exist at all — fall back to static query
                System.debug(LoggingLevel.WARN, 'Dynamic contact query failed, using fallback: ' + e.getMessage());
            }
        }

        // Fallback: static query without moved fields
        return [
            SELECT Id, Name, Title, Email, AccountId
            FROM Contact
            WHERE AccountId = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 501
        ];
    }

    private void populateMovedFields(GraphNode node, Contact c, Relationship_Graph_Config__mdt config) {
        if (config == null) return;

        // Check moved flag
        if (String.isNotBlank(config.Contact_Moved_Flag_Field__c)) {
            Object flagVal = getFieldValue(c, config.Contact_Moved_Flag_Field__c.trim());
            if (flagVal instanceof Boolean) {
                node.hasMovedCompany = (Boolean) flagVal;
            } else if (flagVal != null) {
                // Treat any truthy string as moved
                String strVal = String.valueOf(flagVal).toLowerCase();
                node.hasMovedCompany = strVal == 'true' || strVal == 'yes' || strVal == '1';
            }
        }

        // Previous company
        if (String.isNotBlank(config.Contact_Previous_Company_Field__c)) {
            Object prevVal = getFieldValue(c, config.Contact_Previous_Company_Field__c.trim());
            if (prevVal != null) {
                node.previousCompany = String.valueOf(prevVal);
            }
        }

        // Move info
        if (String.isNotBlank(config.Contact_Moved_Info_Field__c)) {
            Object infoVal = getFieldValue(c, config.Contact_Moved_Info_Field__c.trim());
            if (infoVal != null) {
                node.movedInfo = String.valueOf(infoVal);
            }
        }
    }

    @TestVisible
    private void resolveMovedCompanyIds(GraphData graph) {
        Set<String> companyNames = new Set<String>();
        for (GraphNode node : graph.nodes) {
            if (node.hasMovedCompany == true && String.isNotBlank(node.previousCompany)) {
                companyNames.add(node.previousCompany);
            }
        }
        if (companyNames.isEmpty()) return;

        Map<String, Id> nameToId = new Map<String, Id>();
        for (Account a : [
            SELECT Id, Name FROM Account WHERE Name IN :companyNames WITH SECURITY_ENFORCED
        ]) {
            nameToId.put(a.Name, a.Id);
        }

        for (GraphNode node : graph.nodes) {
            if (node.hasMovedCompany == true && String.isNotBlank(node.previousCompany)) {
                Id acctId = nameToId.get(node.previousCompany);
                if (acctId != null) {
                    node.previousCompanyId = String.valueOf(acctId);
                }
            }
        }
    }

    @TestVisible
    private Object getFieldValue(SObject record, String fieldName) {
        try {
            return record.get(fieldName);
        } catch (Exception e) {
            return null;
        }
    }

    // ─── Account Hierarchy ───────────────────────────────────────────

    @TestVisible
    private void addAccountHierarchy(Id accountId, GraphData graph, Relationship_Graph_Config__mdt config) {
        // Determine parent field (default to ParentId)
        String parentField = 'ParentId';
        if (config != null && String.isNotBlank(config.Parent_Account_Field__c)) {
            parentField = config.Parent_Account_Field__c.trim();
        }

        // Mark the current account node
        for (GraphNode node : graph.nodes) {
            if (node.nodeType == 'Account' && node.id == String.valueOf(accountId)) {
                node.hierarchyLevel = 'current';
                break;
            }
        }

        // Query parent account
        try {
            String parentSoql = 'SELECT ' + String.escapeSingleQuotes(parentField)
                + ' FROM Account WHERE Id = :accountId WITH SECURITY_ENFORCED LIMIT 1';
            List<SObject> parentResults = Database.query(parentSoql);
            if (!parentResults.isEmpty()) {
                Object parentIdVal = parentResults[0].get(parentField);
                if (parentIdVal != null) {
                    Id parentAccountId = Id.valueOf(String.valueOf(parentIdVal));
                    List<Account> parentAccounts = [
                        SELECT Id, Name, Industry
                        FROM Account
                        WHERE Id = :parentAccountId
                        WITH SECURITY_ENFORCED
                        LIMIT 1
                    ];
                    if (!parentAccounts.isEmpty()) {
                        Account parent = parentAccounts[0];
                        GraphNode parentNode = new GraphNode(
                            parent.Id, parent.Name, 'Account', null, null, 0, 0
                        );
                        parentNode.hierarchyLevel = 'parent';
                        parentNode.isHierarchyAccount = true;
                        graph.nodes.add(parentNode);

                        // Edge: current → parent
                        graph.edges.add(new GraphEdge(
                            accountId, parent.Id, 0.8, 0, 'hierarchy'
                        ));
                    }
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Hierarchy parent query failed: ' + e.getMessage());
        }

        // Query child accounts
        try {
            String childSoql = 'SELECT Id, Name, Industry FROM Account WHERE '
                + String.escapeSingleQuotes(parentField) + ' = :accountId'
                + ' WITH SECURITY_ENFORCED LIMIT 20';
            List<Account> children = Database.query(childSoql);
            for (Account child : children) {
                GraphNode childNode = new GraphNode(
                    child.Id, child.Name, 'Account', null, null, 0, 0
                );
                childNode.hierarchyLevel = 'child';
                childNode.isHierarchyAccount = true;
                graph.nodes.add(childNode);

                // Edge: current → child
                graph.edges.add(new GraphEdge(
                    accountId, child.Id, 0.6, 0, 'hierarchy'
                ));
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Hierarchy children query failed: ' + e.getMessage());
        }
    }

    // ─── Inner Classes (serialized to JSON for LWC) ─────────────────

    public class GraphData {
        @AuraEnabled public List<GraphNode> nodes { get; set; }
        @AuraEnabled public List<GraphEdge> edges { get; set; }
        @AuraEnabled public Boolean isTruncated { get; set; }
        @AuraEnabled public Integer totalContactCount { get; set; }
        @AuraEnabled public List<RiskAlert> riskAlerts { get; set; }
        @AuraEnabled public List<String> warnings { get; set; }

        public GraphData() {
            this.nodes = new List<GraphNode>();
            this.edges = new List<GraphEdge>();
            this.isTruncated = false;
            this.totalContactCount = 0;
            this.riskAlerts = new List<RiskAlert>();
            this.warnings = new List<String>();
        }
    }

    public class GraphNode {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String nodeType { get; set; }        // Account, Contact, Opportunity
        @AuraEnabled public String classification { get; set; }  // Champion, Blocker, etc.
        @AuraEnabled public String title { get; set; }           // Job title or stage
        @AuraEnabled public Integer interactionCount { get; set; }
        @AuraEnabled public Integer coOccurrenceCount { get; set; }
        @AuraEnabled public Decimal confidence { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public Decimal amount { get; set; }         // For Opportunity nodes
        @AuraEnabled public Date closeDate { get; set; }         // For Opportunity nodes
        @AuraEnabled public String strengthReason { get; set; }  // AI-generated explanation
        @AuraEnabled public Datetime lastInteractionDate { get; set; }
        @AuraEnabled public Decimal strength { get; set; }
        @AuraEnabled public List<RelationshipStrengthCalculator.FactorBreakdown> strengthFactors { get; set; }
        @AuraEnabled public String accountName { get; set; }        // For External_Contact nodes
        @AuraEnabled public String accountId { get; set; }          // For External_Contact nodes
        @AuraEnabled public Boolean hasMovedCompany { get; set; }   // Contact has left company
        @AuraEnabled public String previousCompany { get; set; }    // Where they moved to
        @AuraEnabled public String previousCompanyId { get; set; }  // Account Id of previous company
        @AuraEnabled public String movedInfo { get; set; }          // Additional move info
        @AuraEnabled public String hierarchyLevel { get; set; }     // 'parent', 'current', 'child'
        @AuraEnabled public Boolean isHierarchyAccount { get; set; } // True for parent/child accounts

        public GraphNode(
            Id recordId, String name, String nodeType, String classification,
            String title, Integer interactionCount, Integer coOccurrenceCount
        ) {
            this.id = String.valueOf(recordId);
            this.name = name;
            this.nodeType = nodeType;
            this.classification = classification;
            this.title = title;
            this.interactionCount = interactionCount;
            this.coOccurrenceCount = coOccurrenceCount;
        }
    }

    public class GraphEdge {
        @AuraEnabled public String source { get; set; }
        @AuraEnabled public String target { get; set; }
        @AuraEnabled public Decimal strength { get; set; }
        @AuraEnabled public Integer interactionCount { get; set; }
        @AuraEnabled public String edgeType { get; set; }
        @AuraEnabled public String label { get; set; }

        public GraphEdge(
            Id sourceId, Id targetId, Decimal strength,
            Integer interactionCount, String edgeType
        ) {
            this.source = String.valueOf(sourceId);
            this.target = String.valueOf(targetId);
            this.strength = strength;
            this.interactionCount = interactionCount;
            this.edgeType = edgeType;
        }
    }

    public class RiskAlert {
        @AuraEnabled public String severity { get; set; }   // high, medium
        @AuraEnabled public String riskType { get; set; }    // stale_champion, no_economic_buyer, etc.
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String contactId { get; set; }   // nullable — some alerts are account-level
        @AuraEnabled public String contactName { get; set; }

        public RiskAlert(String severity, String riskType, String message) {
            this.severity = severity;
            this.riskType = riskType;
            this.message = message;
        }
    }

    // ─── Risk Detection ──────────────────────────────────────────────

    @TestVisible
    private void detectRisks(GraphData graph) {
        List<GraphNode> contactNodes = new List<GraphNode>();
        for (GraphNode node : graph.nodes) {
            if (node.nodeType == 'Contact') {
                contactNodes.add(node);
            }
        }

        // Count classifications for single-threaded and missing-role checks
        Map<String, List<GraphNode>> byClassification = new Map<String, List<GraphNode>>();
        for (GraphNode node : contactNodes) {
            String cls = node.classification != null ? node.classification : 'Unknown';
            if (!byClassification.containsKey(cls)) {
                byClassification.put(cls, new List<GraphNode>());
            }
            byClassification.get(cls).add(node);
        }

        // R1: Stale Champion — no activity in 30+ days
        Datetime staleThreshold = Datetime.now().addDays(-30);
        if (byClassification.containsKey('Champion')) {
            for (GraphNode node : byClassification.get('Champion')) {
                if (node.lastInteractionDate != null && node.lastInteractionDate < staleThreshold) {
                    Long millisDiff = Datetime.now().getTime() - node.lastInteractionDate.getTime();
                    Integer daysSince = (Integer)(millisDiff / (1000 * 60 * 60 * 24));
                    RiskAlert alert = new RiskAlert(
                        'high', 'stale_champion',
                        node.name + ' \u2014 no activity in ' + daysSince + ' days'
                    );
                    alert.contactId = node.id;
                    alert.contactName = node.name;
                    graph.riskAlerts.add(alert);
                }
            }
        }

        // R2: No Economic Buyer
        if (!byClassification.containsKey('Economic Buyer')
            || byClassification.get('Economic Buyer').isEmpty()) {
            graph.riskAlerts.add(new RiskAlert(
                'high', 'no_economic_buyer',
                'No Economic Buyer identified'
            ));
        }

        // R3: Active Blocker/Detractor — high interaction count
        for (String cls : new List<String>{ 'Blocker', 'Detractor' }) {
            if (byClassification.containsKey(cls)) {
                for (GraphNode node : byClassification.get(cls)) {
                    if (node.interactionCount > 5) {
                        RiskAlert alert = new RiskAlert(
                            'high', 'active_blocker',
                            node.name + ' (' + cls + ') is actively engaged'
                        );
                        alert.contactId = node.id;
                        alert.contactName = node.name;
                        graph.riskAlerts.add(alert);
                    }
                }
            }
        }

        // R4: Weak Key Buyer — Economic/Technical Buyer with low strength
        for (String cls : new List<String>{ 'Economic Buyer', 'Technical Buyer' }) {
            if (byClassification.containsKey(cls)) {
                for (GraphNode node : byClassification.get(cls)) {
                    if (node.strength != null && node.strength < 0.3) {
                        RiskAlert alert = new RiskAlert(
                            'medium', 'weak_key_buyer',
                            node.name + ' has a weak relationship'
                        );
                        alert.contactId = node.id;
                        alert.contactName = node.name;
                        graph.riskAlerts.add(alert);
                    }
                }
            }
        }

        // R5: Single-Threaded — only 1 Champion or only 1 Economic Buyer
        for (String cls : new List<String>{ 'Champion', 'Economic Buyer' }) {
            if (byClassification.containsKey(cls)
                && byClassification.get(cls).size() == 1) {
                GraphNode node = byClassification.get(cls)[0];
                RiskAlert alert = new RiskAlert(
                    'medium', 'single_threaded',
                    'Only one ' + cls + ' \u2014 deal at risk if they leave'
                );
                alert.contactId = node.id;
                alert.contactName = node.name;
                graph.riskAlerts.add(alert);
            }
        }

        // R6: Ghost Champion — low confidence
        if (byClassification.containsKey('Champion')) {
            for (GraphNode node : byClassification.get('Champion')) {
                if (node.confidence != null && node.confidence < 0.5) {
                    RiskAlert alert = new RiskAlert(
                        'medium', 'ghost_champion',
                        node.name + ' may not be a true Champion (' +
                        Math.round(node.confidence * 100) + '%)'
                    );
                    alert.contactId = node.id;
                    alert.contactName = node.name;
                    graph.riskAlerts.add(alert);
                }
            }
        }

        // R7: Key contact left company
        for (String cls : new List<String>{ 'Champion', 'Economic Buyer', 'Technical Buyer' }) {
            if (byClassification.containsKey(cls)) {
                for (GraphNode node : byClassification.get(cls)) {
                    if (node.hasMovedCompany == true) {
                        String msg = node.name + ' (' + cls + ') has left the company';
                        if (String.isNotBlank(node.previousCompany)) {
                            msg += ' (moved to ' + node.previousCompany + ')';
                        }
                        RiskAlert alert = new RiskAlert('high', 'contact_left_company', msg);
                        alert.contactId = node.id;
                        alert.contactName = node.name;
                        graph.riskAlerts.add(alert);
                    }
                }
            }
        }
    }
}
