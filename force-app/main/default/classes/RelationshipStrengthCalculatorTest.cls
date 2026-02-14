/**
 * Unit tests for RelationshipStrengthCalculator.
 */
@IsTest
private class RelationshipStrengthCalculatorTest {

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
}
