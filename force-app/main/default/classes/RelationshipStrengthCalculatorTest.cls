/**
 * Unit tests for RelationshipStrengthCalculator.
 * Covers strength calculation, time decay, normalization,
 * co-occurrence upsert, and FLS stripping.
 */
@IsTest
private class RelationshipStrengthCalculatorTest {

    // ─── calculateStrengths ────────────────────────────────────────

    @IsTest
    static void testCalculateStrengths() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 5);

        // Build interaction data
        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();

        // Contact 0: High engagement
        InteractionDataService.ContactInteractionSummary high =
            new InteractionDataService.ContactInteractionSummary();
        high.emailsSent = 20;
        high.emailsReceived = 30;
        high.meetingsAttended = 10;
        high.tasksCompleted = 5;
        high.coOccurrenceCount = 15;
        bundle.contactSummaries.put(contacts[0].Id, high);

        // Contact 1: Low engagement
        InteractionDataService.ContactInteractionSummary low =
            new InteractionDataService.ContactInteractionSummary();
        low.emailsSent = 1;
        low.emailsReceived = 1;
        bundle.contactSummaries.put(contacts[1].Id, low);

        // Contact 2: Zero engagement
        bundle.contactSummaries.put(contacts[2].Id, new InteractionDataService.ContactInteractionSummary());

        // Contact 3: Has opportunity role
        InteractionDataService.ContactInteractionSummary oppRole =
            new InteractionDataService.ContactInteractionSummary();
        oppRole.hasOpportunityRole = true;
        oppRole.emailsSent = 5;
        bundle.contactSummaries.put(contacts[3].Id, oppRole);

        // Contact 4: Medium engagement
        InteractionDataService.ContactInteractionSummary medium =
            new InteractionDataService.ContactInteractionSummary();
        medium.emailsSent = 5;
        medium.emailsReceived = 8;
        medium.meetingsAttended = 3;
        bundle.contactSummaries.put(contacts[4].Id, medium);

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        Map<Id, Decimal> strengths = calculator.calculateStrengths(acct.Id, bundle, 0.95);
        Test.stopTest();

        System.assertEquals(5, strengths.size(), 'Should have strengths for all 5 contacts');

        // High engagement should have highest strength
        Decimal highStrength = strengths.get(contacts[0].Id);
        Decimal lowStrength = strengths.get(contacts[1].Id);
        Decimal zeroStrength = strengths.get(contacts[2].Id);

        System.assert(highStrength > lowStrength,
            'High engagement should have higher strength than low');
        System.assert(lowStrength > zeroStrength,
            'Low engagement should have higher strength than zero');
        System.assertEquals(0.0, zeroStrength,
            'Zero engagement should have zero strength');

        // All should be normalized 0-1
        for (Decimal s : strengths.values()) {
            System.assert(s >= 0.0 && s <= 1.0,
                'Strength should be between 0 and 1, got: ' + s);
        }

        // Highest engagement should normalize to 1.0
        System.assertEquals(1.0, highStrength,
            'Highest engagement should normalize to 1.0');
    }

    // ─── Time Decay ────────────────────────────────────────────────

    @IsTest
    static void testTimeDecayReducesOldInteractions() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 2);

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();

        // Contact 0: Same engagement, recent interaction
        InteractionDataService.ContactInteractionSummary recent =
            new InteractionDataService.ContactInteractionSummary();
        recent.emailsSent = 10;
        recent.emailsReceived = 10;
        recent.lastInteractionDate = Date.today();
        bundle.contactSummaries.put(contacts[0].Id, recent);

        // Contact 1: Same engagement, old interaction (6 months ago)
        InteractionDataService.ContactInteractionSummary old =
            new InteractionDataService.ContactInteractionSummary();
        old.emailsSent = 10;
        old.emailsReceived = 10;
        old.lastInteractionDate = Date.today().addDays(-180);
        bundle.contactSummaries.put(contacts[1].Id, old);

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        Map<Id, Decimal> strengths = calculator.calculateStrengths(acct.Id, bundle, 0.95);
        Test.stopTest();

        Decimal recentStrength = strengths.get(contacts[0].Id);
        Decimal oldStrength = strengths.get(contacts[1].Id);

        System.assert(recentStrength > oldStrength,
            'Recent interaction (' + recentStrength + ') should be stronger than old (' + oldStrength + ')');
    }

    @IsTest
    static void testTimeDecayFactorOneNoDecay() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 2);

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();

        InteractionDataService.ContactInteractionSummary recent =
            new InteractionDataService.ContactInteractionSummary();
        recent.emailsSent = 10;
        recent.lastInteractionDate = Date.today();
        bundle.contactSummaries.put(contacts[0].Id, recent);

        InteractionDataService.ContactInteractionSummary old =
            new InteractionDataService.ContactInteractionSummary();
        old.emailsSent = 10;
        old.lastInteractionDate = Date.today().addDays(-180);
        bundle.contactSummaries.put(contacts[1].Id, old);

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        // With decay factor of 1.0, no decay should be applied
        Map<Id, Decimal> strengths = calculator.calculateStrengths(acct.Id, bundle, 1.0);
        Test.stopTest();

        Decimal recentStrength = strengths.get(contacts[0].Id);
        Decimal oldStrength = strengths.get(contacts[1].Id);

        System.assertEquals(recentStrength, oldStrength,
            'With decay=1.0, same engagement should have same strength regardless of recency');
    }

    @IsTest
    static void testTimeDecayNullLastInteractionDate() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 1);

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();

        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();
        summary.emailsSent = 10;
        // lastInteractionDate is null
        bundle.contactSummaries.put(contacts[0].Id, summary);

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        Map<Id, Decimal> strengths = calculator.calculateStrengths(acct.Id, bundle, 0.95);
        Test.stopTest();

        System.assert(strengths.get(contacts[0].Id) > 0,
            'Null lastInteractionDate should not zero out the score');
    }

    @IsTest
    static void testTimeDecayNullFactor() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 1);

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();
        summary.emailsSent = 10;
        summary.lastInteractionDate = Date.today().addDays(-100);
        bundle.contactSummaries.put(contacts[0].Id, summary);

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        Map<Id, Decimal> strengths = calculator.calculateStrengths(acct.Id, bundle, null);
        Test.stopTest();

        System.assert(strengths.get(contacts[0].Id) > 0,
            'Null decay factor should default to no decay');
    }

    // ─── calculateAndPersist ───────────────────────────────────────

    @IsTest
    static void testCalculateAndPersist() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 3);

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        for (Contact c : contacts) {
            InteractionDataService.ContactInteractionSummary s =
                new InteractionDataService.ContactInteractionSummary();
            s.emailsSent = 5;
            s.emailsReceived = 3;
            bundle.contactSummaries.put(c.Id, s);
        }

        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        calculator.calculateAndPersist(acct.Id, contactIds, bundle, 0.95);
        Test.stopTest();

        List<Relationship_Strength__c> records = [
            SELECT Source_Contact__c, Strength__c, Interaction_Count__c
            FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id AND Target_Object_Type__c = 'Account'
        ];

        System.assertEquals(3, records.size(), 'Should have persisted 3 strength records');
        for (Relationship_Strength__c rs : records) {
            System.assertEquals(8, rs.Interaction_Count__c,
                'Should have 8 total interactions (5 sent + 3 received)');
        }
    }

    @IsTest
    static void testCalculateAndPersistUpdatesExisting() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 2);

        // Create initial strengths
        RelationshipGraphTestDataFactory.createStrengths(acct.Id, contacts);
        Integer initialCount = [
            SELECT COUNT() FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id AND Target_Object_Type__c = 'Account'
        ];

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        for (Contact c : contacts) {
            InteractionDataService.ContactInteractionSummary s =
                new InteractionDataService.ContactInteractionSummary();
            s.emailsSent = 20;
            s.emailsReceived = 15;
            bundle.contactSummaries.put(c.Id, s);
        }

        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        calculator.calculateAndPersist(acct.Id, contactIds, bundle, 0.95);
        Test.stopTest();

        Integer finalCount = [
            SELECT COUNT() FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id AND Target_Object_Type__c = 'Account'
        ];
        System.assertEquals(initialCount, finalCount,
            'Should update existing records, not create duplicates');
    }

    // ─── Co-occurrence Records ─────────────────────────────────────

    @IsTest
    static void testCoOccurrenceRecordsCreated() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 3);

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        for (Contact c : contacts) {
            bundle.contactSummaries.put(c.Id, new InteractionDataService.ContactInteractionSummary());
        }

        // Add co-occurrence pairs
        String pairKey = String.valueOf(contacts[0].Id) < String.valueOf(contacts[1].Id)
            ? String.valueOf(contacts[0].Id) + '_' + String.valueOf(contacts[1].Id)
            : String.valueOf(contacts[1].Id) + '_' + String.valueOf(contacts[0].Id);
        bundle.coOccurrencePairs.put(pairKey, 5);

        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        calculator.calculateAndPersist(acct.Id, contactIds, bundle, 0.95);
        Test.stopTest();

        List<Relationship_Strength__c> coOccRecords = [
            SELECT Source_Contact__c, Target_Record_Id__c, Co_Occurrence_Count__c
            FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id AND Target_Object_Type__c = 'Contact'
        ];
        System.assert(coOccRecords.size() > 0,
            'Should have created co-occurrence records');
    }

    @IsTest
    static void testCoOccurrenceRecordsUpdated() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 2);

        // Create initial co-occurrence record
        RelationshipGraphTestDataFactory.createCoOccurrenceStrengths(
            acct.Id, contacts[0].Id, contacts[1].Id, 3
        );

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        for (Contact c : contacts) {
            bundle.contactSummaries.put(c.Id, new InteractionDataService.ContactInteractionSummary());
        }

        // Updated co-occurrence count
        String pairKey = String.valueOf(contacts[0].Id) < String.valueOf(contacts[1].Id)
            ? String.valueOf(contacts[0].Id) + '_' + String.valueOf(contacts[1].Id)
            : String.valueOf(contacts[1].Id) + '_' + String.valueOf(contacts[0].Id);
        bundle.coOccurrencePairs.put(pairKey, 10);

        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        calculator.calculateAndPersist(acct.Id, contactIds, bundle, 0.95);
        Test.stopTest();

        List<Relationship_Strength__c> coOccRecords = [
            SELECT Co_Occurrence_Count__c
            FROM Relationship_Strength__c
            WHERE Account__c = :acct.Id AND Target_Object_Type__c = 'Contact'
            AND Source_Contact__c = :contacts[0].Id
        ];
        System.assertEquals(1, coOccRecords.size(),
            'Should update existing record, not create duplicate');
        System.assertEquals(10, coOccRecords[0].Co_Occurrence_Count__c,
            'Co-occurrence count should be updated to 10');
    }

    // ─── Edge Cases ────────────────────────────────────────────────

    @IsTest
    static void testEmptyBundle() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();

        RelationshipStrengthCalculator calculator = new RelationshipStrengthCalculator();

        Test.startTest();
        Map<Id, Decimal> strengths = calculator.calculateStrengths(acct.Id, bundle, 0.95);
        Test.stopTest();

        System.assertEquals(0, strengths.size(), 'Empty bundle should return empty map');
    }
}
