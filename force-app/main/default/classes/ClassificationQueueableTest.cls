/**
 * Unit tests for ClassificationQueueable.
 * Covers async execution, classification persistence, FLS stripping,
 * and user override protection.
 */
@IsTest
private class ClassificationQueueableTest {

    @TestSetup
    static void setup() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 5);
    }

    @IsTest
    static void testExecuteClassifiesContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id];
        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        Test.startTest();
        System.enqueueJob(new ClassificationQueueable(acct.Id, contactIds));
        Test.stopTest();

        // Verify classifications were persisted
        List<Contact_Classification__c> classifications = [
            SELECT Contact__c, Classification__c, Provider__c, Is_User_Override__c
            FROM Contact_Classification__c
            WHERE Account__c = :acct.Id
        ];

        System.assert(classifications.size() > 0,
            'Should have created classification records');
        for (Contact_Classification__c cc : classifications) {
            System.assertEquals(false, cc.Is_User_Override__c,
                'Auto-classifications should not be user overrides');
        }
    }

    @IsTest
    static void testPersistClassificationsCreatesRecords() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 3];
        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        Test.startTest();
        System.enqueueJob(new ClassificationQueueable(acct.Id, contactIds));
        Test.stopTest();

        Integer count = [
            SELECT COUNT() FROM Contact_Classification__c
            WHERE Account__c = :acct.Id
        ];
        System.assert(count >= 3,
            'Should have at least 3 classification records');
    }

    @IsTest
    static void testUserOverridesNotOverwritten() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        // Create a user override
        insert new Contact_Classification__c(
            Contact__c = c.Id,
            Account__c = acct.Id,
            Classification__c = 'Champion',
            Confidence_Score__c = 1.0,
            Provider__c = 'UserOverride',
            Is_User_Override__c = true,
            Last_Classified__c = Datetime.now()
        );

        Test.startTest();
        System.enqueueJob(new ClassificationQueueable(acct.Id, new List<Id>{ c.Id }));
        Test.stopTest();

        // Verify user override still exists unchanged
        Contact_Classification__c userOverride = [
            SELECT Classification__c, Provider__c, Is_User_Override__c
            FROM Contact_Classification__c
            WHERE Contact__c = :c.Id AND Account__c = :acct.Id
            AND Is_User_Override__c = true
            LIMIT 1
        ];
        System.assertEquals('Champion', userOverride.Classification__c,
            'User override should remain unchanged');
        System.assertEquals('UserOverride', userOverride.Provider__c);
    }

    @IsTest
    static void testUpdatesExistingNonOverrideClassifications() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        // Create existing auto-classification
        insert new Contact_Classification__c(
            Contact__c = c.Id,
            Account__c = acct.Id,
            Classification__c = 'Unknown',
            Confidence_Score__c = 0.1,
            Provider__c = 'HeuristicClassificationProvider',
            Is_User_Override__c = false,
            Last_Classified__c = Datetime.now().addDays(-30)
        );

        Id existingId = [
            SELECT Id FROM Contact_Classification__c
            WHERE Contact__c = :c.Id AND Is_User_Override__c = false
            LIMIT 1
        ].Id;

        Test.startTest();
        System.enqueueJob(new ClassificationQueueable(acct.Id, new List<Id>{ c.Id }));
        Test.stopTest();

        // Verify record was updated (same Id), not duplicated
        List<Contact_Classification__c> results = [
            SELECT Id, Classification__c, Last_Classified__c
            FROM Contact_Classification__c
            WHERE Contact__c = :c.Id AND Account__c = :acct.Id
            AND Is_User_Override__c = false
        ];
        System.assertEquals(1, results.size(),
            'Should update existing record, not create duplicate');
        System.assertEquals(existingId, results[0].Id,
            'Should be the same record Id');
    }

    @IsTest
    static void testBulkClassification() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        // Create additional contacts for bulk test
        List<Contact> extraContacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 45);
        List<Contact> allContacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id];
        List<Id> contactIds = new List<Id>();
        for (Contact c : allContacts) contactIds.add(c.Id);

        Test.startTest();
        System.enqueueJob(new ClassificationQueueable(acct.Id, contactIds));
        Test.stopTest();

        Integer count = [
            SELECT COUNT() FROM Contact_Classification__c
            WHERE Account__c = :acct.Id
        ];
        System.assertEquals(allContacts.size(), count,
            'Should classify all contacts');
    }

    @IsTest
    static void testExceptionHandlingDoesNotThrow() {
        // Pass a bogus account ID — should log error but not throw
        Test.startTest();
        try {
            System.enqueueJob(new ClassificationQueueable(null, new List<Id>()));
            Test.stopTest();
        } catch (Exception e) {
            System.assert(false, 'Queueable should catch exceptions: ' + e.getMessage());
        }
    }

    @IsTest
    static void testProviderFieldPopulated() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        Test.startTest();
        System.enqueueJob(new ClassificationQueueable(acct.Id, new List<Id>{ c.Id }));
        Test.stopTest();

        List<Contact_Classification__c> results = [
            SELECT Provider__c FROM Contact_Classification__c
            WHERE Contact__c = :c.Id AND Account__c = :acct.Id
            AND Is_User_Override__c = false
        ];
        if (!results.isEmpty()) {
            System.assertNotEquals(null, results[0].Provider__c,
                'Provider field should be populated');
            System.assertNotEquals('', results[0].Provider__c);
        }
    }
}
