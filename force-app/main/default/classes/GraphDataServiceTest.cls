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
}
