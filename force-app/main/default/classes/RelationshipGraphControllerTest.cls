/**
 * Unit tests for RelationshipGraphController.
 */
@IsTest
private class RelationshipGraphControllerTest {

    @TestSetup
    static void setup() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 5);
        RelationshipGraphTestDataFactory.createClassifications(acct.Id, contacts, 'Champion');
        RelationshipGraphTestDataFactory.createStrengths(acct.Id, contacts);
    }

    @IsTest
    static void testGetGraphData() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        GraphDataService.GraphData result = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return graph data');
        System.assert(result.nodes.size() > 0, 'Should have nodes');
    }

    @IsTest
    static void testGetGraphDataNullId() {
        Test.startTest();
        try {
            RelationshipGraphController.getGraphData(null, false, 0, 90);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Account ID is required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetNodeDetailContact() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        RelationshipGraphController.NodeDetail detail =
            RelationshipGraphController.getNodeDetail(c.Id);
        Test.stopTest();

        System.assertNotEquals(null, detail, 'Should return node detail');
        System.assertEquals('Contact', detail.objectType);
        System.assertNotEquals(null, detail.name);
    }

    @IsTest
    static void testGetNodeDetailAccount() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        RelationshipGraphController.NodeDetail detail =
            RelationshipGraphController.getNodeDetail(acct.Id);
        Test.stopTest();

        System.assertEquals('Account', detail.objectType);
        System.assertEquals('Test Corp', detail.name);
    }

    @IsTest
    static void testOverrideClassification() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        RelationshipGraphController.overrideClassification(
            c.Id, acct.Id, 'Blocker'
        );
        Test.stopTest();

        Contact_Classification__c cc = [
            SELECT Classification__c, Is_User_Override__c, Provider__c
            FROM Contact_Classification__c
            WHERE Contact__c = :c.Id AND Account__c = :acct.Id
            AND Is_User_Override__c = true
            LIMIT 1
        ];

        System.assertEquals('Blocker', cc.Classification__c);
        System.assertEquals(true, cc.Is_User_Override__c);
        System.assertEquals('UserOverride', cc.Provider__c);
    }

    @IsTest
    static void testOverrideClassificationInvalid() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        try {
            RelationshipGraphController.overrideClassification(
                c.Id, acct.Id, 'InvalidClassification'
            );
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Invalid classification'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetGraphConfig() {
        Test.startTest();
        Map<String, Object> config = RelationshipGraphController.getGraphConfig();
        Test.stopTest();

        System.assertNotEquals(null, config, 'Should return config');
        System.assert(config.containsKey('classifications'), 'Should include classifications list');
    }

    @IsTest
    static void testRefreshGraphData() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        GraphDataService.GraphData result = RelationshipGraphController.refreshGraphData(
            acct.Id, false, 0, 90
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return refreshed graph data');
    }
}
