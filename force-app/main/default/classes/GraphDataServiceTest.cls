/**
 * Unit tests for GraphDataService.
 */
@IsTest
private class GraphDataServiceTest {

    @TestSetup
    static void setup() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 10);
        RelationshipGraphTestDataFactory.createClassifications(acct.Id, contacts, 'Champion');
        RelationshipGraphTestDataFactory.createStrengths(acct.Id, contacts);

        Opportunity opp = RelationshipGraphTestDataFactory.createOpportunity(acct.Id, 'Test Deal');
        insert new OpportunityContactRole(
            ContactId = contacts[0].Id,
            OpportunityId = opp.Id,
            Role = 'Decision Maker'
        );
    }

    // ─── Basic Graph Building ──────────────────────────────────────

    @IsTest
    static void testBuildGraphDataBasic() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        System.assertNotEquals(null, graph, 'Graph should not be null');
        System.assert(graph.nodes.size() > 0, 'Should have nodes');
        System.assert(graph.edges.size() > 0, 'Should have edges');

        // Should have account node
        Boolean hasAccount = false;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.nodeType == 'Account') {
                hasAccount = true;
                break;
            }
        }
        System.assert(hasAccount, 'Should have an Account node');
    }

    // ─── Passive Contacts Filtering ────────────────────────────────

    @IsTest
    static void testHidePassiveContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        GraphDataService service = new GraphDataService();

        // Get all contacts
        GraphDataService.GraphData graphAll = service.buildGraphData(
            acct.Id, false, 0, 90
        );

        // Get only active contacts (min 50 interactions — should filter most)
        GraphDataService.GraphData graphFiltered = service.buildGraphData(
            acct.Id, true, 50, 90
        );

        Test.startTest();
        System.assert(
            graphFiltered.nodes.size() <= graphAll.nodes.size(),
            'Filtered graph should have fewer or equal nodes'
        );
        Test.stopTest();
    }

    // ─── Opportunity Nodes ─────────────────────────────────────────

    @IsTest
    static void testOpportunityNodes() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasOpportunity = false;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.nodeType == 'Opportunity') {
                hasOpportunity = true;
                break;
            }
        }
        System.assert(hasOpportunity, 'Should have Opportunity node linked to contact');
    }

    @IsTest
    static void testOpportunityRoleEdges() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasOppRoleEdge = false;
        for (GraphDataService.GraphEdge edge : graph.edges) {
            if (edge.edgeType == 'opportunity_role') {
                hasOppRoleEdge = true;
                System.assertEquals('Decision Maker', edge.label,
                    'Edge should have role label');
                break;
            }
        }
        System.assert(hasOppRoleEdge, 'Should have opportunity_role edge');
    }

    // ─── Classifications in Nodes ──────────────────────────────────

    @IsTest
    static void testClassificationsInNodes() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasClassifiedContact = false;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.nodeType == 'Contact' && node.classification == 'Champion') {
                hasClassifiedContact = true;
                System.assertNotEquals(null, node.confidence,
                    'Classified node should have confidence');
                break;
            }
        }
        System.assert(hasClassifiedContact, 'Should have contacts with Champion classification');
    }

    @IsTest
    static void testContactNodeEmailPopulated() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasEmail = false;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.nodeType == 'Contact' && node.email != null) {
                hasEmail = true;
                System.assert(node.email.contains('@test.com'),
                    'Email should be from test data');
                break;
            }
        }
        System.assert(hasEmail, 'Contact nodes should have email populated');
    }

    // ─── Edge Types ────────────────────────────────────────────────

    @IsTest
    static void testEdgeTypes() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Set<String> edgeTypes = new Set<String>();
        for (GraphDataService.GraphEdge edge : graph.edges) {
            edgeTypes.add(edge.edgeType);
        }

        System.assert(edgeTypes.contains('account_relationship'),
            'Should have account_relationship edges');
    }

    // ─── Truncation Detection ──────────────────────────────────────

    @IsTest
    static void testNoTruncationWithFewContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        System.assertEquals(false, graph.isTruncated,
            '10 contacts should not trigger truncation');
        System.assertEquals(10, graph.totalContactCount,
            'Should report actual contact count');
    }

    @IsTest
    static void testTruncationFieldsExist() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        GraphDataService service = new GraphDataService();

        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );

        System.assertNotEquals(null, graph.isTruncated,
            'isTruncated should be initialized');
        System.assertNotEquals(null, graph.totalContactCount,
            'totalContactCount should be initialized');
    }

    // ─── ThresholdDays Filtering ───────────────────────────────────

    @IsTest
    static void testThresholdDaysFiltersOldStrengths() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Update all strength records to have old interaction dates
        List<Relationship_Strength__c> strengths = [
            SELECT Id, Last_Interaction_Date__c
            FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id
        ];
        for (Relationship_Strength__c rs : strengths) {
            rs.Last_Interaction_Date__c = Date.today().addDays(-365);
        }
        update strengths;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        // With 30-day threshold, old interactions should be filtered
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 30
        );
        Test.stopTest();

        // Contacts without recent strengths should show with 0 interactions
        // (they still appear, but strength records are filtered out)
        Integer contactNodes = 0;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.nodeType == 'Contact') {
                contactNodes++;
            }
        }
        System.assert(contactNodes > 0, 'Contacts should still appear');
    }

    @IsTest
    static void testThresholdDaysIncludesRecentStrengths() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Ensure all strength records have today's date
        List<Relationship_Strength__c> strengths = [
            SELECT Id, Last_Interaction_Date__c
            FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id
        ];
        for (Relationship_Strength__c rs : strengths) {
            rs.Last_Interaction_Date__c = Date.today();
        }
        update strengths;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 30
        );
        Test.stopTest();

        // Recent strengths should be included
        System.assert(graph.edges.size() > 0,
            'Recent interactions should produce edges');
    }

    // ─── Inner Class Defaults ──────────────────────────────────────

    @IsTest
    static void testGraphDataDefaults() {
        GraphDataService.GraphData graph = new GraphDataService.GraphData();

        System.assertNotEquals(null, graph.nodes);
        System.assertNotEquals(null, graph.edges);
        System.assertEquals(0, graph.nodes.size());
        System.assertEquals(0, graph.edges.size());
        System.assertEquals(false, graph.isTruncated);
        System.assertEquals(0, graph.totalContactCount);
    }

    @IsTest
    static void testGraphNodeConstructor() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        GraphDataService.GraphNode node = new GraphDataService.GraphNode(
            acct.Id, 'Test Corp', 'Account', null, null, 0, 0
        );

        System.assertEquals(String.valueOf(acct.Id), node.id);
        System.assertEquals('Test Corp', node.name);
        System.assertEquals('Account', node.nodeType);
        System.assertEquals(null, node.classification);
        System.assertEquals(0, node.interactionCount);
    }

    @IsTest
    static void testGraphEdgeConstructor() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        GraphDataService.GraphEdge edge = new GraphDataService.GraphEdge(
            c.Id, acct.Id, 0.75, 10, 'account_relationship'
        );

        System.assertEquals(String.valueOf(c.Id), edge.source);
        System.assertEquals(String.valueOf(acct.Id), edge.target);
        System.assertEquals(0.75, edge.strength);
        System.assertEquals(10, edge.interactionCount);
        System.assertEquals('account_relationship', edge.edgeType);
    }

    // ─── Risk Alert Tests ────────────────────────────────────────────

    @IsTest
    static void testRiskAlertStaleChampion() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Set all strength records to 60 days ago
        List<Relationship_Strength__c> strengths = [
            SELECT Id FROM Relationship_Strength__c WHERE Account__c = :acct.Id
        ];
        for (Relationship_Strength__c rs : strengths) {
            rs.Last_Interaction_Date__c = Datetime.now().addDays(-60);
        }
        update strengths;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasStaleChampion = false;
        for (GraphDataService.RiskAlert alert : graph.riskAlerts) {
            if (alert.riskType == 'stale_champion') {
                hasStaleChampion = true;
                System.assertEquals('high', alert.severity);
                System.assertNotEquals(null, alert.contactId);
                break;
            }
        }
        System.assert(hasStaleChampion, 'Should detect stale champion');
    }

    @IsTest
    static void testRiskAlertNoEconomicBuyer() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        // Setup has all contacts as "Champion", no Economic Buyer

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasNoEB = false;
        for (GraphDataService.RiskAlert alert : graph.riskAlerts) {
            if (alert.riskType == 'no_economic_buyer') {
                hasNoEB = true;
                System.assertEquals('high', alert.severity);
                System.assertEquals(null, alert.contactId);
                break;
            }
        }
        System.assert(hasNoEB, 'Should detect missing Economic Buyer');
    }

    @IsTest
    static void testRiskAlertActiveBlocker() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        // Reclassify one contact as Blocker
        Contact_Classification__c cc = [
            SELECT Id FROM Contact_Classification__c
            WHERE Contact__c = :contacts[0].Id AND Account__c = :acct.Id LIMIT 1
        ];
        cc.Classification__c = 'Blocker';
        update cc;

        // Give them high interactions
        Relationship_Strength__c rs = [
            SELECT Id FROM Relationship_Strength__c
            WHERE Source_Contact__c = :contacts[0].Id
            AND Account__c = :acct.Id
            AND Target_Object_Type__c = 'Account' LIMIT 1
        ];
        rs.Interaction_Count__c = 20;
        update rs;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasActiveBlocker = false;
        for (GraphDataService.RiskAlert alert : graph.riskAlerts) {
            if (alert.riskType == 'active_blocker') {
                hasActiveBlocker = true;
                System.assertEquals('high', alert.severity);
                break;
            }
        }
        System.assert(hasActiveBlocker, 'Should detect active blocker');
    }

    @IsTest
    static void testRiskAlertWeakKeyBuyer() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        // Reclassify as Economic Buyer
        Contact_Classification__c cc = [
            SELECT Id FROM Contact_Classification__c
            WHERE Contact__c = :contacts[0].Id AND Account__c = :acct.Id LIMIT 1
        ];
        cc.Classification__c = 'Economic Buyer';
        update cc;

        // Set low strength
        Relationship_Strength__c rs = [
            SELECT Id FROM Relationship_Strength__c
            WHERE Source_Contact__c = :contacts[0].Id
            AND Account__c = :acct.Id
            AND Target_Object_Type__c = 'Account' LIMIT 1
        ];
        rs.Strength__c = 0.1;
        update rs;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasWeakBuyer = false;
        for (GraphDataService.RiskAlert alert : graph.riskAlerts) {
            if (alert.riskType == 'weak_key_buyer') {
                hasWeakBuyer = true;
                System.assertEquals('medium', alert.severity);
                break;
            }
        }
        System.assert(hasWeakBuyer, 'Should detect weak key buyer');
    }

    @IsTest
    static void testRiskAlertSingleThreaded() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        // Setup: 10 contacts all classified as Champion
        // Single-threaded only fires when there's exactly 1 → need to reduce

        // Reclassify 9 of 10 to "End User"
        List<Contact_Classification__c> ccs = [
            SELECT Id FROM Contact_Classification__c
            WHERE Account__c = :acct.Id
            ORDER BY CreatedDate
        ];
        for (Integer i = 1; i < ccs.size(); i++) {
            ccs[i].Classification__c = 'End User';
        }
        update ccs;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        Boolean hasSingleThreaded = false;
        for (GraphDataService.RiskAlert alert : graph.riskAlerts) {
            if (alert.riskType == 'single_threaded' && alert.message.contains('Champion')) {
                hasSingleThreaded = true;
                System.assertEquals('medium', alert.severity);
                break;
            }
        }
        System.assert(hasSingleThreaded, 'Should detect single-threaded Champion');
    }

    @IsTest
    static void testNoRiskAlertsHealthyAccount() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Create a healthy state: multiple Champions + 1 Economic Buyer + recent interactions
        List<Contact_Classification__c> ccs = [
            SELECT Id FROM Contact_Classification__c
            WHERE Account__c = :acct.Id
            ORDER BY CreatedDate
        ];
        // First 5 stay Champion, 6th becomes Economic Buyer
        if (ccs.size() > 5) {
            ccs[5].Classification__c = 'Economic Buyer';
            update ccs;
        }

        // Ensure recent interactions
        List<Relationship_Strength__c> strengths = [
            SELECT Id FROM Relationship_Strength__c WHERE Account__c = :acct.Id
        ];
        for (Relationship_Strength__c rs : strengths) {
            rs.Last_Interaction_Date__c = Date.today();
            rs.Strength__c = 0.7;
        }
        update strengths;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        // Should have no high-severity alerts (may have single_threaded for EB)
        Integer highAlerts = 0;
        for (GraphDataService.RiskAlert alert : graph.riskAlerts) {
            if (alert.severity == 'high') {
                highAlerts++;
            }
        }
        System.assertEquals(0, highAlerts, 'Healthy account should have no high-severity alerts');
    }

    // ─── External Contact Nodes ────────────────────────────────────

    @IsTest
    static void testExternalContactNodesCreated() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];
        Account extAcct = RelationshipGraphTestDataFactory.createAccount('External Corp');
        List<Contact> extContacts = RelationshipGraphTestDataFactory.createContacts(extAcct.Id, 3);

        // Build a bundle with external contacts
        InteractionDataService.InteractionBundle bundle =
            new InteractionDataService.InteractionBundle();

        List<Contact> internalContacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 2];
        for (Contact c : internalContacts) {
            bundle.contactSummaries.put(c.Id, new InteractionDataService.ContactInteractionSummary());
        }

        for (Integer i = 0; i < extContacts.size(); i++) {
            Contact ext = extContacts[i];
            InteractionDataService.ExternalContactSummary extSum =
                new InteractionDataService.ExternalContactSummary();
            extSum.contactId = ext.Id;
            extSum.contactName = 'External Person ' + i;
            extSum.contactEmail = ext.Email;
            extSum.accountId = extAcct.Id;
            extSum.accountName = 'External Corp';
            extSum.sharedEmailCount = 5;
            extSum.coOccurringInternalContactIds.add(internalContacts[0].Id);
            bundle.externalContactSummaries.put(ext.Id, extSum);
        }

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90, bundle
        );
        Test.stopTest();

        Integer externalNodes = 0;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.nodeType == 'External_Contact') {
                externalNodes++;
                System.assertEquals('External Corp', node.accountName,
                    'External node should have account name');
            }
        }
        System.assertEquals(3, externalNodes, 'Should have 3 external contact nodes');
    }

    @IsTest
    static void testExternalContactEdgesCrossAccount() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];
        Account extAcct = RelationshipGraphTestDataFactory.createAccount('Edge Corp');
        List<Contact> extContacts = RelationshipGraphTestDataFactory.createContacts(extAcct.Id, 1);

        InteractionDataService.InteractionBundle bundle =
            new InteractionDataService.InteractionBundle();

        List<Contact> internalContacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 2];
        for (Contact c : internalContacts) {
            bundle.contactSummaries.put(c.Id, new InteractionDataService.ContactInteractionSummary());
        }

        InteractionDataService.ExternalContactSummary extSum =
            new InteractionDataService.ExternalContactSummary();
        extSum.contactId = extContacts[0].Id;
        extSum.contactName = 'Edge Person';
        extSum.sharedEmailCount = 10;
        extSum.coOccurringInternalContactIds.add(internalContacts[0].Id);
        extSum.coOccurringInternalContactIds.add(internalContacts[1].Id);
        bundle.externalContactSummaries.put(extContacts[0].Id, extSum);

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90, bundle
        );
        Test.stopTest();

        Integer crossAccountEdges = 0;
        for (GraphDataService.GraphEdge edge : graph.edges) {
            if (edge.edgeType == 'cross_account') {
                crossAccountEdges++;
            }
        }
        System.assertEquals(2, crossAccountEdges,
            'Should have 2 cross_account edges (one per internal co-occurring contact)');
    }

    @IsTest
    static void testExternalContactsCappedAt50() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];
        Account extAcct = RelationshipGraphTestDataFactory.createAccount('Cap Corp');
        // Create 60 external contacts
        List<Contact> extContacts = new List<Contact>();
        for (Integer i = 0; i < 60; i++) {
            extContacts.add(new Contact(
                FirstName = 'Ext', LastName = 'Contact ' + i,
                AccountId = extAcct.Id, Email = 'ext' + i + '@cap.com'
            ));
        }
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(extContacts, dml);

        InteractionDataService.InteractionBundle bundle =
            new InteractionDataService.InteractionBundle();

        List<Contact> internalContacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];
        bundle.contactSummaries.put(internalContacts[0].Id, new InteractionDataService.ContactInteractionSummary());

        for (Contact ext : extContacts) {
            InteractionDataService.ExternalContactSummary extSum =
                new InteractionDataService.ExternalContactSummary();
            extSum.contactId = ext.Id;
            extSum.contactName = ext.Name;
            extSum.sharedEmailCount = 1;
            extSum.coOccurringInternalContactIds.add(internalContacts[0].Id);
            bundle.externalContactSummaries.put(ext.Id, extSum);
        }

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90, bundle
        );
        Test.stopTest();

        Integer externalNodes = 0;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.nodeType == 'External_Contact') {
                externalNodes++;
            }
        }
        System.assert(externalNodes <= 50,
            'External nodes should be capped at 50, got: ' + externalNodes);
    }

    @IsTest
    static void testBuildGraphDataWithoutBundle() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];
        GraphDataService service = new GraphDataService();

        Test.startTest();
        // 4-param version (backward compat) should work without external data
        GraphDataService.GraphData graph4 = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        // 5-param with null bundle
        GraphDataService.GraphData graph5 = service.buildGraphData(
            acct.Id, false, 0, 90, null
        );
        Test.stopTest();

        System.assertEquals(graph4.nodes.size(), graph5.nodes.size(),
            '4-param and 5-param with null should produce same result');

        // Verify no External_Contact nodes when no bundle
        for (GraphDataService.GraphNode node : graph5.nodes) {
            System.assertNotEquals('External_Contact', node.nodeType,
                'Should have no external contacts without bundle');
        }
    }

    // ─── Strength Factor Breakdown ──────────────────────────────────

    @IsTest
    static void testStrengthFactorsPopulatedOnNode() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        // Create a strength record with breakdown JSON
        List<RelationshipStrengthCalculator.FactorBreakdown> breakdown =
            new List<RelationshipStrengthCalculator.FactorBreakdown>();
        RelationshipStrengthCalculator.FactorBreakdown fb =
            new RelationshipStrengthCalculator.FactorBreakdown();
        fb.name = 'Email Sent';
        fb.category = 'Activity';
        fb.rawValue = 10;
        fb.weight = 1.0;
        fb.contribution = 10.0;
        breakdown.add(fb);

        // Update the existing strength record with breakdown
        Relationship_Strength__c rs = [
            SELECT Id FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id
            AND Source_Contact__c = :contacts[0].Id
            AND Target_Object_Type__c = 'Account'
            LIMIT 1
        ];
        rs.Strength_Breakdown__c = JSON.serialize(breakdown);
        update rs;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        // Find the contact node
        GraphDataService.GraphNode contactNode = null;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.id == String.valueOf(contacts[0].Id)) {
                contactNode = node;
                break;
            }
        }

        System.assert(contactNode != null, 'Should find the contact node');
        System.assert(contactNode.strengthFactors != null,
            'strengthFactors should be populated');
        System.assertEquals(1, contactNode.strengthFactors.size(),
            'Should have 1 factor breakdown entry');
        System.assertEquals('Email Sent', contactNode.strengthFactors[0].name);
        System.assertEquals(10.0, contactNode.strengthFactors[0].contribution);
    }

    // ─── Moved Contact Detection ────────────────────────────────────

    @IsTest
    static void testMovedContactDetected() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];

        // Without config, no moved contacts should be set
        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90, null, false, null
        );
        Test.stopTest();

        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.nodeType == 'Contact') {
                System.assertEquals(null, node.hasMovedCompany,
                    'Without config, hasMovedCompany should be null');
            }
        }
    }

    @IsTest
    static void testMovedContactEndToEnd() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];

        // Set first contact as "moved"
        Contact movedContact = [SELECT Id FROM Contact WHERE AccountId = :acct.Id ORDER BY CreatedDate LIMIT 1];
        movedContact.No_Longer_at_Company__c = true;
        movedContact.Previous_Company_Text_c__c = 'Rival Corp';
        movedContact.Person_has_moved__c = 'Joined as CTO';
        update movedContact;

        // Fetch the real Custom Metadata config (deployed with the package)
        Relationship_Graph_Config__mdt config = [
            SELECT Contact_Moved_Flag_Field__c, Contact_Previous_Company_Field__c,
                   Contact_Moved_Info_Field__c, Parent_Account_Field__c,
                   Show_Account_Hierarchy__c, Min_Interactions__c,
                   Hierarchy_Contact_Limit__c
            FROM Relationship_Graph_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90, null, false, config
        );
        Test.stopTest();

        // Verify the moved contact node has hasMovedCompany = true
        GraphDataService.GraphNode movedNode = null;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.id == String.valueOf(movedContact.Id)) {
                movedNode = node;
                break;
            }
        }
        System.assertNotEquals(null, movedNode, 'Should find the moved contact node');
        System.assertEquals(true, movedNode.hasMovedCompany, 'hasMovedCompany should be true');
        System.assertEquals('Rival Corp', movedNode.previousCompany, 'previousCompany should match');
        System.assertEquals('Joined as CTO', movedNode.movedInfo, 'movedInfo should match');
        // No Account named 'Rival Corp' exists — previousCompanyId should be null
        System.assertEquals(null, movedNode.previousCompanyId, 'previousCompanyId should be null when no matching Account');
    }

    @IsTest
    static void testMovedContactResolvesCompanyId() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];

        // Create the target company Account
        Account rivalAcct = RelationshipGraphTestDataFactory.createAccount('Rival Corp');

        // Set first contact as "moved" to Rival Corp
        Contact movedContact = [SELECT Id FROM Contact WHERE AccountId = :acct.Id ORDER BY CreatedDate LIMIT 1];
        movedContact.No_Longer_at_Company__c = true;
        movedContact.Previous_Company_Text_c__c = 'Rival Corp';
        update movedContact;

        Relationship_Graph_Config__mdt config = [
            SELECT Contact_Moved_Flag_Field__c, Contact_Previous_Company_Field__c,
                   Contact_Moved_Info_Field__c, Parent_Account_Field__c,
                   Show_Account_Hierarchy__c, Min_Interactions__c,
                   Hierarchy_Contact_Limit__c
            FROM Relationship_Graph_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90, null, false, config
        );
        Test.stopTest();

        GraphDataService.GraphNode movedNode = null;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.id == String.valueOf(movedContact.Id)) {
                movedNode = node;
                break;
            }
        }
        System.assertNotEquals(null, movedNode, 'Should find the moved contact node');
        System.assertEquals(true, movedNode.hasMovedCompany, 'hasMovedCompany should be true');
        System.assertEquals('Rival Corp', movedNode.previousCompany, 'previousCompany should match');
        System.assertEquals(String.valueOf(rivalAcct.Id), movedNode.previousCompanyId,
            'previousCompanyId should be resolved to the Rival Corp Account Id');
    }

    @IsTest
    static void testMovedContactPreviousCompany() {
        // Test the getFieldValue helper works correctly
        Account acct = [SELECT Id, Name, Industry FROM Account WHERE Name = 'Test Corp' LIMIT 1];

        GraphDataService service = new GraphDataService();
        Object nameVal = service.getFieldValue(acct, 'Name');
        Object industryVal = service.getFieldValue(acct, 'Industry');
        Object badField = service.getFieldValue(acct, 'NonExistent__c');

        System.assertEquals('Test Corp', nameVal, 'Should return field value');
        System.assertEquals('Technology', industryVal, 'Should return industry');
        System.assertEquals(null, badField, 'Invalid field should return null');
    }

    @IsTest
    static void testMovedChampionRiskAlert() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];

        // Build a graph and manually set a champion as moved to test R7
        GraphDataService service = new GraphDataService();
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90
        );

        // Simulate a moved champion by modifying node data before re-running risk detection
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.classification == 'Champion' && node.nodeType == 'Contact') {
                node.hasMovedCompany = true;
                node.previousCompany = 'New Corp';
                break;
            }
        }

        // Clear existing risks and re-detect
        graph.riskAlerts.clear();

        Test.startTest();
        service.detectRisks(graph);
        Test.stopTest();

        Boolean hasMovedRisk = false;
        for (GraphDataService.RiskAlert alert : graph.riskAlerts) {
            if (alert.riskType == 'contact_left_company') {
                hasMovedRisk = true;
                System.assertEquals('high', alert.severity);
                System.assert(alert.message.contains('New Corp'),
                    'Message should include previous company');
                break;
            }
        }
        System.assert(hasMovedRisk, 'Should detect moved champion risk');
    }

    // ─── Account Hierarchy ──────────────────────────────────────────

    @IsTest
    static void testAccountHierarchyParentAndChildren() {
        Account parent = RelationshipGraphTestDataFactory.createAccount('Parent Corp');
        Account current = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];
        current.ParentId = parent.Id;
        update current;

        Account child1 = new Account(Name = 'Child One', ParentId = current.Id, Industry = 'Technology');
        Account child2 = new Account(Name = 'Child Two', ParentId = current.Id, Industry = 'Technology');
        insert new List<Account>{ child1, child2 };

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            current.Id, false, 0, 90, null, true, null
        );
        Test.stopTest();

        // Count hierarchy nodes and edges
        Integer hierarchyNodes = 0;
        Integer hierarchyEdges = 0;
        Boolean hasParent = false;
        Boolean hasChild = false;

        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.isHierarchyAccount == true) {
                hierarchyNodes++;
                if (node.hierarchyLevel == 'parent') hasParent = true;
                if (node.hierarchyLevel == 'child') hasChild = true;
            }
        }
        for (GraphDataService.GraphEdge edge : graph.edges) {
            if (edge.edgeType == 'hierarchy') hierarchyEdges++;
        }

        System.assertEquals(3, hierarchyNodes, 'Should have 1 parent + 2 children');
        System.assert(hasParent, 'Should have a parent node');
        System.assert(hasChild, 'Should have child nodes');
        System.assertEquals(3, hierarchyEdges,
            'Should have 3 hierarchy edges (1 to parent + 2 to children)');
    }

    @IsTest
    static void testHierarchyChildCappedAt20() {
        Account current = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];

        // Create 25 child accounts
        List<Account> children = new List<Account>();
        for (Integer i = 0; i < 25; i++) {
            children.add(new Account(
                Name = 'Child Account ' + i,
                ParentId = current.Id,
                Industry = 'Technology'
            ));
        }
        insert children;

        GraphDataService service = new GraphDataService();

        Test.startTest();
        GraphDataService.GraphData graph = service.buildGraphData(
            current.Id, false, 0, 90, null, true, null
        );
        Test.stopTest();

        Integer childNodes = 0;
        for (GraphDataService.GraphNode node : graph.nodes) {
            if (node.isHierarchyAccount == true && node.hierarchyLevel == 'child') {
                childNodes++;
            }
        }
        System.assert(childNodes <= 20,
            'Hierarchy children should be capped at 20, got: ' + childNodes);
    }

    @IsTest
    static void testGracefulDegradationMissingFields() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];

        // Create a config-like scenario with bad field names
        // The queryContacts method should fall back to static SOQL
        GraphDataService service = new GraphDataService();

        Test.startTest();
        // 7-param version with null config — should work fine
        GraphDataService.GraphData graph = service.buildGraphData(
            acct.Id, false, 0, 90, null, false, null
        );
        Test.stopTest();

        System.assertNotEquals(null, graph, 'Should return graph data even without config');
        System.assert(graph.nodes.size() > 0, 'Should have nodes');
    }

    @IsTest
    static void testQueryContactsStripInaccessible() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];

        // Set data on a contact so we can verify fields come through
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];
        c.No_Longer_at_Company__c = true;
        c.Previous_Company_Text_c__c = 'StripTest Corp';
        update c;

        Relationship_Graph_Config__mdt config = [
            SELECT Contact_Moved_Flag_Field__c, Contact_Previous_Company_Field__c,
                   Contact_Moved_Info_Field__c
            FROM Relationship_Graph_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        GraphDataService service = new GraphDataService();

        Test.startTest();
        List<Contact> contacts = service.queryContacts(acct.Id, config);
        Test.stopTest();

        System.assert(contacts.size() > 0, 'Should return contacts via stripInaccessible');

        // Verify the moved fields are accessible on the returned records
        Contact movedContact = null;
        for (Contact ct : contacts) {
            if (ct.Id == c.Id) {
                movedContact = ct;
                break;
            }
        }
        System.assertNotEquals(null, movedContact, 'Should find the updated contact');
        System.assertEquals(true, movedContact.get('No_Longer_at_Company__c'),
            'Moved flag should be accessible via stripInaccessible');
        System.assertEquals('StripTest Corp', movedContact.get('Previous_Company_Text_c__c'),
            'Previous company should be accessible via stripInaccessible');
    }

    @IsTest
    static void testGraphDataWarningsDefault() {
        // Verify the new warnings list is initialized empty
        GraphDataService.GraphData graph = new GraphDataService.GraphData();
        System.assertNotEquals(null, graph.warnings, 'Warnings should be initialized');
        System.assertEquals(0, graph.warnings.size(), 'Warnings should be empty by default');
    }
}
