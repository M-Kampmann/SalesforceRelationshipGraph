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
}
