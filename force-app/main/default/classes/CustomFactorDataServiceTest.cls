/**
 * Unit tests for CustomFactorDataService.
 * Tests Contact_Field and Record_Count factor value fetching,
 * schema validation, and error handling.
 */
@IsTest
private class CustomFactorDataServiceTest {

    @IsTest
    static void testFetchContactFieldFactor() {
        // Use a standard numeric Contact field that exists in all orgs
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 2);

        // Build a Contact_Field factor pointing to a standard numeric field
        // Using MailingLatitude which is a Double on Contact
        StrengthFactorService.StrengthFactor factor = new StrengthFactorService.StrengthFactor();
        factor.developerName = 'Test_Latitude';
        factor.label = 'Test Latitude';
        factor.weight = 1.0;
        factor.sourceType = 'Contact_Field';
        factor.sourceValue = 'MailingLatitude';
        factor.category = 'Test';

        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        CustomFactorDataService service = new CustomFactorDataService();

        Test.startTest();
        Map<Id, Map<String, Decimal>> result = service.fetchCustomFactors(
            contactIds, new List<StrengthFactorService.StrengthFactor>{ factor }
        );
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should have results for both contacts');
        // Values should be 0 since we didn't set MailingLatitude
        for (Id cId : contactIds) {
            System.assert(result.containsKey(cId), 'Should have entry for contact');
            System.assert(result.get(cId).containsKey('Test_Latitude'),
                'Should have factor value');
        }
    }

    @IsTest
    static void testFetchRecordCountFactor() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 2);

        // Create some Tasks for contact 0
        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < 5; i++) {
            tasks.add(new Task(
                WhoId = contacts[0].Id,
                Subject = 'Test Task ' + i,
                Status = 'Completed',
                ActivityDate = Date.today()
            ));
        }
        // 2 tasks for contact 1
        for (Integer i = 0; i < 2; i++) {
            tasks.add(new Task(
                WhoId = contacts[1].Id,
                Subject = 'Test Task ' + i,
                Status = 'Completed',
                ActivityDate = Date.today()
            ));
        }
        insert tasks;

        // Build a Record_Count factor for Task.WhoId
        StrengthFactorService.StrengthFactor factor = new StrengthFactorService.StrengthFactor();
        factor.developerName = 'Task_Count';
        factor.label = 'Task Count';
        factor.weight = 2.0;
        factor.sourceType = 'Record_Count';
        factor.sourceValue = 'Task.WhoId';
        factor.category = 'Activity';

        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        CustomFactorDataService service = new CustomFactorDataService();

        Test.startTest();
        Map<Id, Map<String, Decimal>> result = service.fetchCustomFactors(
            contactIds, new List<StrengthFactorService.StrengthFactor>{ factor }
        );
        Test.stopTest();

        System.assertEquals(5, result.get(contacts[0].Id).get('Task_Count'),
            'Contact 0 should have 5 tasks');
        System.assertEquals(2, result.get(contacts[1].Id).get('Task_Count'),
            'Contact 1 should have 2 tasks');
    }

    @IsTest
    static void testInvalidFieldNameIgnored() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 1);

        StrengthFactorService.StrengthFactor factor = new StrengthFactorService.StrengthFactor();
        factor.developerName = 'Bad_Field';
        factor.label = 'Bad Field';
        factor.weight = 1.0;
        factor.sourceType = 'Contact_Field';
        factor.sourceValue = 'Nonexistent_Field__c';
        factor.category = 'Test';

        Set<Id> contactIds = new Set<Id>{ contacts[0].Id };

        CustomFactorDataService service = new CustomFactorDataService();

        Test.startTest();
        Map<Id, Map<String, Decimal>> result = service.fetchCustomFactors(
            contactIds, new List<StrengthFactorService.StrengthFactor>{ factor }
        );
        Test.stopTest();

        // Should not throw, should return empty factor map for the contact
        System.assertEquals(1, result.size());
        System.assert(!result.get(contacts[0].Id).containsKey('Bad_Field'),
            'Invalid field should be skipped');
    }

    @IsTest
    static void testInvalidObjectNameIgnored() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 1);

        StrengthFactorService.StrengthFactor factor = new StrengthFactorService.StrengthFactor();
        factor.developerName = 'Bad_Object';
        factor.label = 'Bad Object';
        factor.weight = 1.0;
        factor.sourceType = 'Record_Count';
        factor.sourceValue = 'NonexistentObject__c.Contact__c';
        factor.category = 'Test';

        Set<Id> contactIds = new Set<Id>{ contacts[0].Id };

        CustomFactorDataService service = new CustomFactorDataService();

        Test.startTest();
        Map<Id, Map<String, Decimal>> result = service.fetchCustomFactors(
            contactIds, new List<StrengthFactorService.StrengthFactor>{ factor }
        );
        Test.stopTest();

        System.assertEquals(1, result.size());
        System.assert(!result.get(contacts[0].Id).containsKey('Bad_Object'),
            'Invalid object should be skipped');
    }

    @IsTest
    static void testEmptyContactIds() {
        CustomFactorDataService service = new CustomFactorDataService();

        StrengthFactorService.StrengthFactor factor = new StrengthFactorService.StrengthFactor();
        factor.developerName = 'Test';
        factor.sourceType = 'Contact_Field';
        factor.sourceValue = 'MailingLatitude';

        Test.startTest();
        Map<Id, Map<String, Decimal>> result = service.fetchCustomFactors(
            new Set<Id>(), new List<StrengthFactorService.StrengthFactor>{ factor }
        );
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Empty contactIds should return empty map');
    }

    @IsTest
    static void testNoCustomFactors() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 2);

        Set<Id> contactIds = new Set<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        CustomFactorDataService service = new CustomFactorDataService();

        Test.startTest();
        Map<Id, Map<String, Decimal>> result = service.fetchCustomFactors(
            contactIds, new List<StrengthFactorService.StrengthFactor>()
        );
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should initialize maps for all contacts');
        for (Id cId : contactIds) {
            System.assertEquals(0, result.get(cId).size(),
                'Should have empty factor map when no factors configured');
        }
    }

    @IsTest
    static void testNonNumericFieldIgnored() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 1);

        // LastName is a Text field — should be skipped
        StrengthFactorService.StrengthFactor factor = new StrengthFactorService.StrengthFactor();
        factor.developerName = 'Name_Test';
        factor.label = 'Name Test';
        factor.weight = 1.0;
        factor.sourceType = 'Contact_Field';
        factor.sourceValue = 'LastName';
        factor.category = 'Test';

        Set<Id> contactIds = new Set<Id>{ contacts[0].Id };

        CustomFactorDataService service = new CustomFactorDataService();

        Test.startTest();
        Map<Id, Map<String, Decimal>> result = service.fetchCustomFactors(
            contactIds, new List<StrengthFactorService.StrengthFactor>{ factor }
        );
        Test.stopTest();

        System.assert(!result.get(contacts[0].Id).containsKey('Name_Test'),
            'Non-numeric field should be skipped');
    }

    @IsTest
    static void testInvalidRecordCountFormat() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 1);

        // Bad format: no dot separator
        StrengthFactorService.StrengthFactor factor = new StrengthFactorService.StrengthFactor();
        factor.developerName = 'Bad_Format';
        factor.label = 'Bad Format';
        factor.weight = 1.0;
        factor.sourceType = 'Record_Count';
        factor.sourceValue = 'NoDotHere';
        factor.category = 'Test';

        Set<Id> contactIds = new Set<Id>{ contacts[0].Id };

        CustomFactorDataService service = new CustomFactorDataService();

        Test.startTest();
        Map<Id, Map<String, Decimal>> result = service.fetchCustomFactors(
            contactIds, new List<StrengthFactorService.StrengthFactor>{ factor }
        );
        Test.stopTest();

        System.assert(!result.get(contacts[0].Id).containsKey('Bad_Format'),
            'Bad format should be skipped');
    }
}
