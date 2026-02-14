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
                break;
            }
        }
        System.assert(hasClassifiedContact, 'Should have contacts with Champion classification');
    }

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
}
