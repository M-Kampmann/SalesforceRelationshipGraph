/**
 * Unit tests for HeuristicClassificationProvider.
 */
@IsTest
private class HeuristicClassificationProviderTest {

    @IsTest
    static void testClassifyCEO() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        Contact ceo = new Contact(
            FirstName = 'John', LastName = 'CEO', AccountId = acct.Id,
            Email = 'john@test.com', Title = 'CEO'
        );
        insert ceo;

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        bundle.contactSummaries.put(ceo.Id, new InteractionDataService.ContactInteractionSummary());

        HeuristicClassificationProvider provider = new HeuristicClassificationProvider();

        Test.startTest();
        Map<Id, ClassificationResult> results = provider.classifyContacts(
            acct.Id, new List<Id>{ ceo.Id }, bundle
        );
        Test.stopTest();

        System.assertNotEquals(null, results.get(ceo.Id), 'Should have result for CEO contact');
        System.assertEquals('Economic Buyer', results.get(ceo.Id).classification,
            'CEO should be classified as Economic Buyer');
    }

    @IsTest
    static void testClassifyCTO() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        Contact cto = new Contact(
            FirstName = 'Jane', LastName = 'CTO', AccountId = acct.Id,
            Email = 'jane@test.com', Title = 'CTO'
        );
        insert cto;

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        bundle.contactSummaries.put(cto.Id, new InteractionDataService.ContactInteractionSummary());

        HeuristicClassificationProvider provider = new HeuristicClassificationProvider();

        Test.startTest();
        Map<Id, ClassificationResult> results = provider.classifyContacts(
            acct.Id, new List<Id>{ cto.Id }, bundle
        );
        Test.stopTest();

        System.assertEquals('Technical Buyer', results.get(cto.Id).classification,
            'CTO should be classified as Technical Buyer');
    }

    @IsTest
    static void testHighEngagementChampion() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        Contact champion = new Contact(
            FirstName = 'Champion', LastName = 'User', AccountId = acct.Id,
            Email = 'champion@test.com', Title = 'Manager'
        );
        insert champion;

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();
        summary.emailsSent = 10;
        summary.emailsReceived = 15;
        summary.meetingsAttended = 8;
        summary.tasksCompleted = 5;
        summary.positiveSignalCount = 5;
        bundle.contactSummaries.put(champion.Id, summary);

        HeuristicClassificationProvider provider = new HeuristicClassificationProvider();

        Test.startTest();
        Map<Id, ClassificationResult> results = provider.classifyContacts(
            acct.Id, new List<Id>{ champion.Id }, bundle
        );
        Test.stopTest();

        System.assertEquals('Champion', results.get(champion.Id).classification,
            'Highly engaged contact should be classified as Champion');
    }

    @IsTest
    static void testDetractorNegativeSignals() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        Contact detractor = new Contact(
            FirstName = 'Negative', LastName = 'Nancy', AccountId = acct.Id,
            Email = 'nancy@test.com', Title = 'Specialist'
        );
        insert detractor;

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();
        summary.emailsSent = 1;
        summary.emailsReceived = 1;
        summary.meetingsDeclined = 5;
        summary.negativeSignalCount = 5;
        bundle.contactSummaries.put(detractor.Id, summary);

        HeuristicClassificationProvider provider = new HeuristicClassificationProvider();

        Test.startTest();
        Map<Id, ClassificationResult> results = provider.classifyContacts(
            acct.Id, new List<Id>{ detractor.Id }, bundle
        );
        Test.stopTest();

        String classification = results.get(detractor.Id).classification;
        System.assert(
            classification == 'Detractor' || classification == 'Blocker',
            'Contact with negative signals should be Detractor or Blocker, got: ' + classification
        );
    }

    @IsTest
    static void testProviderIsAlwaysAvailable() {
        HeuristicClassificationProvider provider = new HeuristicClassificationProvider();
        System.assertEquals(true, provider.isAvailable(), 'Heuristic provider should always be available');
        System.assertEquals('HeuristicClassificationProvider', provider.getProviderName());
    }

    @IsTest
    static void testOpportunityRoleSignal() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        Contact c = new Contact(
            FirstName = 'Decision', LastName = 'Maker', AccountId = acct.Id,
            Email = 'dm@test.com'
        );
        insert c;

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();
        summary.hasOpportunityRole = true;
        summary.opportunityRole = 'Decision Maker';
        summary.emailsSent = 3;
        summary.emailsReceived = 3;
        bundle.contactSummaries.put(c.Id, summary);

        HeuristicClassificationProvider provider = new HeuristicClassificationProvider();

        Test.startTest();
        Map<Id, ClassificationResult> results = provider.classifyContacts(
            acct.Id, new List<Id>{ c.Id }, bundle
        );
        Test.stopTest();

        System.assertEquals('Economic Buyer', results.get(c.Id).classification,
            'Decision Maker role should classify as Economic Buyer');
    }

    @IsTest
    static void testBulkClassification() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 50);

        InteractionDataService.InteractionBundle bundle = new InteractionDataService.InteractionBundle();
        for (Contact c : contacts) {
            bundle.contactSummaries.put(c.Id, new InteractionDataService.ContactInteractionSummary());
        }

        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) {
            contactIds.add(c.Id);
        }

        HeuristicClassificationProvider provider = new HeuristicClassificationProvider();

        Test.startTest();
        Map<Id, ClassificationResult> results = provider.classifyContacts(
            acct.Id, contactIds, bundle
        );
        Test.stopTest();

        System.assertEquals(50, results.size(), 'Should have results for all 50 contacts');
        for (ClassificationResult result : results.values()) {
            System.assert(result.isValid(), 'All results should be valid');
        }
    }
}
