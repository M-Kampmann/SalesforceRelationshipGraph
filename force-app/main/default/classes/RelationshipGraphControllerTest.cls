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
        Opportunity opp = RelationshipGraphTestDataFactory.createOpportunity(acct.Id, 'Test Deal');
    }

    // ─── getGraphData ──────────────────────────────────────────────

    @IsTest
    static void testGetGraphData() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        GraphDataService.GraphData result = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 90, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return graph data');
        System.assert(result.nodes.size() > 0, 'Should have nodes');
        System.assertNotEquals(null, result.isTruncated, 'Should have truncation flag');
        System.assertEquals(false, result.isTruncated, '5 contacts should not be truncated');
        System.assertEquals(5, result.totalContactCount, 'Should report total contact count');
    }

    @IsTest
    static void testGetGraphDataNullId() {
        Test.startTest();
        try {
            RelationshipGraphController.getGraphData(null, false, 0, 90, null, null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Account ID is required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testGetGraphDataWithThresholdDays() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // With very tight threshold (1 day), contacts with recent data should appear
        GraphDataService.GraphData result = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 1, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result);
        // Strength records have Last_Interaction_Date__c = today, so should pass threshold
    }

    // ─── getNodeDetail ─────────────────────────────────────────────

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
        System.assertNotEquals(null, detail.recordId);
    }

    @IsTest
    static void testGetNodeDetailContactWithClassification() {
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        RelationshipGraphController.NodeDetail detail =
            RelationshipGraphController.getNodeDetail(c.Id);
        Test.stopTest();

        System.assertEquals('Champion', detail.classification,
            'Contact should have Champion classification from test setup');
        System.assertNotEquals(null, detail.confidence);
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
        System.assertEquals('Technology', detail.industry);
    }

    @IsTest
    static void testGetNodeDetailOpportunity() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];

        Test.startTest();
        RelationshipGraphController.NodeDetail detail =
            RelationshipGraphController.getNodeDetail(opp.Id);
        Test.stopTest();

        System.assertEquals('Opportunity', detail.objectType);
        System.assertEquals('Test Deal', detail.name);
        System.assertEquals('Prospecting', detail.stage);
        System.assertEquals(50000, detail.amount);
        System.assertNotEquals(null, detail.closeDate);
    }

    @IsTest
    static void testGetNodeDetailNullId() {
        Test.startTest();
        try {
            RelationshipGraphController.getNodeDetail(null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Record ID is required'));
        }
        Test.stopTest();
    }

    // ─── overrideClassification ────────────────────────────────────

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
            SELECT Classification__c, Is_User_Override__c, Provider__c, Confidence_Score__c
            FROM Contact_Classification__c
            WHERE Contact__c = :c.Id AND Account__c = :acct.Id
            AND Is_User_Override__c = true
            LIMIT 1
        ];

        System.assertEquals('Blocker', cc.Classification__c);
        System.assertEquals(true, cc.Is_User_Override__c);
        System.assertEquals('UserOverride', cc.Provider__c);
        System.assertEquals(1.0, cc.Confidence_Score__c,
            'User override should have full confidence');
    }

    @IsTest
    static void testOverrideClassificationUpdatesExisting() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact LIMIT 1];

        // First override
        RelationshipGraphController.overrideClassification(c.Id, acct.Id, 'Blocker');
        Id firstId = [
            SELECT Id FROM Contact_Classification__c
            WHERE Contact__c = :c.Id AND Is_User_Override__c = true LIMIT 1
        ].Id;

        Test.startTest();
        // Second override should update, not create new
        RelationshipGraphController.overrideClassification(c.Id, acct.Id, 'Champion');
        Test.stopTest();

        List<Contact_Classification__c> overrides = [
            SELECT Id, Classification__c
            FROM Contact_Classification__c
            WHERE Contact__c = :c.Id AND Account__c = :acct.Id
            AND Is_User_Override__c = true
        ];
        System.assertEquals(1, overrides.size(),
            'Should update existing override, not create duplicate');
        System.assertEquals('Champion', overrides[0].Classification__c);
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

    // ─── getGraphConfig ────────────────────────────────────────────

    @IsTest
    static void testGetGraphConfig() {
        Test.startTest();
        Map<String, Object> config = RelationshipGraphController.getGraphConfig();
        Test.stopTest();

        System.assertNotEquals(null, config, 'Should return config');
        System.assert(config.containsKey('classifications'), 'Should include classifications list');
        System.assert(config.containsKey('classificationProvider'));
        System.assert(config.containsKey('activityThresholdDays'));
        System.assert(config.containsKey('minInteractions'));
        System.assert(config.containsKey('timeDecayFactor'));
        System.assert(config.containsKey('cacheTTLMinutes'));
    }

    @IsTest
    static void testGetGraphConfigClassificationsList() {
        Map<String, Object> config = RelationshipGraphController.getGraphConfig();
        List<String> classifications = (List<String>) config.get('classifications');

        System.assertNotEquals(null, classifications);
        System.assertEquals(8, classifications.size(),
            'Should have 8 classification options');
    }

    // ─── refreshGraphData ──────────────────────────────────────────

    @IsTest
    static void testRefreshGraphData() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        GraphDataService.GraphData result = RelationshipGraphController.refreshGraphData(
            acct.Id, false, 0, 90, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return refreshed graph data');
        System.assert(result.nodes.size() > 0, 'Should have nodes after refresh');
    }

    @IsTest
    static void testRefreshGraphDataNullId() {
        Test.startTest();
        try {
            RelationshipGraphController.refreshGraphData(null, false, 0, 90, null, null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Account ID is required'));
        }
        Test.stopTest();
    }

    // ─── External Contacts ─────────────────────────────────────────

    @IsTest
    static void testGetGraphDataWithExternalContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        GraphDataService.GraphData result = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 90, true, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return graph data with external flag');
        System.assert(result.nodes.size() > 0, 'Should have nodes');
    }

    @IsTest
    static void testRefreshGraphDataWithExternalContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        GraphDataService.GraphData result = RelationshipGraphController.refreshGraphData(
            acct.Id, false, 0, 90, true, null
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return refreshed data with external flag');
        System.assert(result.nodes.size() > 0, 'Should have nodes');
    }

    @IsTest
    static void testGetGraphDataBackwardCompat() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // null showExternalContacts should behave identically to false
        GraphDataService.GraphData resultNull = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 90, null, null
        );
        GraphDataService.GraphData resultFalse = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 90, false, null
        );
        Test.stopTest();

        System.assertEquals(resultNull.nodes.size(), resultFalse.nodes.size(),
            'null and false should produce same node count');
    }

    // ─── refreshGraphData (continued) ───────────────────────────────

    @IsTest
    static void testRefreshGraphDataCreatesStrengths() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        // Delete existing strengths to verify refresh creates them
        delete [SELECT Id FROM Relationship_Strength__c WHERE Account__c = :acct.Id];

        Test.startTest();
        RelationshipGraphController.refreshGraphData(acct.Id, false, 0, 90, null, null);
        Test.stopTest();

        Integer strengthCount = [
            SELECT COUNT() FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id
        ];
        System.assert(strengthCount > 0,
            'Refresh should create strength records');
    }

    // ─── Account Hierarchy + Moved Contact ──────────────────────────

    @IsTest
    static void testGetGraphConfigIncludesNewFields() {
        Map<String, Object> config = RelationshipGraphController.getGraphConfig();

        System.assert(config.containsKey('showAccountHierarchy'),
            'Config should include showAccountHierarchy');
        System.assert(config.containsKey('contactMovedFlagField'),
            'Config should include contactMovedFlagField');
        System.assert(config.containsKey('parentAccountField'),
            'Config should include parentAccountField');
        System.assert(config.containsKey('hierarchyContactLimit'),
            'Config should include hierarchyContactLimit');
    }

    @IsTest
    static void testGetGraphDataWithHierarchy() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        GraphDataService.GraphData result = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 90, null, true
        );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Should return graph data with hierarchy flag');
        System.assert(result.nodes.size() > 0, 'Should have nodes');
    }

    @IsTest
    static void testGetGraphDataBackwardCompatSixthParam() {
        Account acct = [SELECT Id FROM Account LIMIT 1];

        Test.startTest();
        // null showHierarchy should behave identically to false
        GraphDataService.GraphData resultNull = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 90, null, null
        );
        GraphDataService.GraphData resultFalse = RelationshipGraphController.getGraphData(
            acct.Id, false, 0, 90, null, false
        );
        Test.stopTest();

        System.assertEquals(resultNull.nodes.size(), resultFalse.nodes.size(),
            'null and false showHierarchy should produce same node count');
    }

    @IsTest
    static void testCacheKeyIsAlphanumeric() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];
        String key = RelationshipGraphController.buildCacheKey(
            acct.Id, true, 3, true, true
        );
        System.assert(key.isAlphanumeric(),
            'Cache key must be alphanumeric for Platform Cache: ' + key);
    }

    @IsTest
    static void testCacheKeyUniqueness() {
        Account acct = [SELECT Id FROM Account WHERE Name = 'Test Corp' LIMIT 1];
        String key1 = RelationshipGraphController.buildCacheKey(acct.Id, true, 3, false, false);
        String key2 = RelationshipGraphController.buildCacheKey(acct.Id, false, 3, false, false);
        String key3 = RelationshipGraphController.buildCacheKey(acct.Id, true, 3, true, false);
        String key4 = RelationshipGraphController.buildCacheKey(acct.Id, true, 3, false, true);
        System.assertNotEquals(key1, key2, 'Different hidePassive should produce different keys');
        System.assertNotEquals(key1, key3, 'Different showExternalContacts should produce different keys');
        System.assertNotEquals(key1, key4, 'Different showHierarchy should produce different keys');
    }
}
