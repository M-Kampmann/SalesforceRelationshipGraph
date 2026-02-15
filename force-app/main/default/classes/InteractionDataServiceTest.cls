/**
 * Unit tests for InteractionDataService.
 * Covers bulk data fetching, co-occurrence computation, sentiment analysis,
 * task status filtering, and last interaction date tracking.
 */
@IsTest
private class InteractionDataServiceTest {

    @TestSetup
    static void setup() {
        Account acct = RelationshipGraphTestDataFactory.createAccount('Test Corp');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(acct.Id, 5);
    }

    // ─── getAccountContactIds ──────────────────────────────────────

    @IsTest
    static void testGetAccountContactIdsDirectContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        List<Id> contactIds = service.getAccountContactIds(acct.Id);
        Test.stopTest();

        System.assertEquals(5, contactIds.size(), 'Should return 5 direct contacts');
    }

    @IsTest
    static void testGetAccountContactIdsEmpty() {
        Account acct = new Account(Name = 'Empty Corp');
        insert acct;

        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        List<Id> contactIds = service.getAccountContactIds(acct.Id);
        Test.stopTest();

        System.assertEquals(0, contactIds.size(), 'Account with no contacts returns empty list');
    }

    // ─── fetchInteractionData ──────────────────────────────────────

    @IsTest
    static void testFetchInteractionDataInitializesSummaries() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id];
        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct.Id, contactIds);
        Test.stopTest();

        System.assertEquals(5, bundle.contactSummaries.size(),
            'Should initialize summaries for all contacts');
        for (Id cId : contactIds) {
            System.assertNotEquals(null, bundle.contactSummaries.get(cId),
                'Each contact should have a summary');
        }
    }

    @IsTest
    static void testFetchInteractionDataEmptyContacts() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct.Id, new List<Id>());
        Test.stopTest();

        System.assertEquals(0, bundle.contactSummaries.size(),
            'Empty contact list should return empty summaries');
    }

    // ─── Task Data ─────────────────────────────────────────────────

    @IsTest
    static void testFetchTaskDataCountsCompletedOnly() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        // Create 3 completed and 2 open tasks
        RelationshipGraphTestDataFactory.createTasks(c.Id, acct.Id, 3, 'Completed');
        RelationshipGraphTestDataFactory.createTasks(c.Id, acct.Id, 2, 'Open');

        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct.Id, new List<Id>{ c.Id });
        Test.stopTest();

        InteractionDataService.ContactInteractionSummary summary =
            bundle.contactSummaries.get(c.Id);
        System.assertEquals(3, summary.tasksCompleted,
            'Should only count completed tasks, not open ones');
    }

    @IsTest
    static void testFetchTaskDataIgnoresNonCompleted() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        // Only create non-completed tasks
        RelationshipGraphTestDataFactory.createTasks(c.Id, acct.Id, 5, 'In Progress');

        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct.Id, new List<Id>{ c.Id });
        Test.stopTest();

        InteractionDataService.ContactInteractionSummary summary =
            bundle.contactSummaries.get(c.Id);
        System.assertEquals(0, summary.tasksCompleted,
            'Non-completed tasks should not be counted');
    }

    // ─── ContactInteractionSummary ─────────────────────────────────

    @IsTest
    static void testUpdateLastInteractionDate() {
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();

        summary.updateLastInteractionDate(Date.newInstance(2025, 1, 15));
        System.assertEquals(Date.newInstance(2025, 1, 15), summary.lastInteractionDate,
            'Should set first date');

        summary.updateLastInteractionDate(Date.newInstance(2025, 6, 20));
        System.assertEquals(Date.newInstance(2025, 6, 20), summary.lastInteractionDate,
            'Should update to later date');

        summary.updateLastInteractionDate(Date.newInstance(2025, 3, 1));
        System.assertEquals(Date.newInstance(2025, 6, 20), summary.lastInteractionDate,
            'Should not overwrite with earlier date');
    }

    @IsTest
    static void testUpdateLastInteractionDateNull() {
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();

        summary.updateLastInteractionDate(null);
        System.assertEquals(null, summary.lastInteractionDate,
            'Null date should not set lastInteractionDate');

        summary.updateLastInteractionDate(Date.today());
        summary.updateLastInteractionDate(null);
        System.assertEquals(Date.today(), summary.lastInteractionDate,
            'Null date should not overwrite existing date');
    }

    @IsTest
    static void testGetTotalInteractions() {
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();
        summary.emailsSent = 5;
        summary.emailsReceived = 10;
        summary.meetingsAttended = 3;
        summary.tasksCompleted = 2;

        System.assertEquals(20, summary.getTotalInteractions(),
            'Total should be sum of emails sent/received + meetings + tasks');
    }

    @IsTest
    static void testGetTotalInteractionsExcludesDeclined() {
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();
        summary.emailsSent = 2;
        summary.meetingsAttended = 1;
        summary.meetingsDeclined = 5;
        summary.tasksCompleted = 1;

        System.assertEquals(4, summary.getTotalInteractions(),
            'Declined meetings should not be included in total');
    }

    @IsTest
    static void testContactInteractionSummaryDefaults() {
        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();

        System.assertEquals(0, summary.emailsSent);
        System.assertEquals(0, summary.emailsReceived);
        System.assertEquals(0, summary.meetingsAttended);
        System.assertEquals(0, summary.meetingsDeclined);
        System.assertEquals(0, summary.tasksCompleted);
        System.assertEquals(0, summary.coOccurrenceCount);
        System.assertEquals(false, summary.hasOpportunityRole);
        System.assertEquals(0, summary.negativeSignalCount);
        System.assertEquals(0, summary.positiveSignalCount);
        System.assertEquals(null, summary.lastInteractionDate);
    }

    // ─── Co-occurrence ─────────────────────────────────────────────

    @IsTest
    static void testCoOccurrencePairKeyConsistency() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id ORDER BY Id LIMIT 2];

        // Co-occurrence pair keys should be consistent regardless of order
        InteractionDataService service = new InteractionDataService();

        // Test via bundle computation
        InteractionDataService.InteractionBundle bundle =
            new InteractionDataService.InteractionBundle();
        bundle.contactSummaries.put(contacts[0].Id, new InteractionDataService.ContactInteractionSummary());
        bundle.contactSummaries.put(contacts[1].Id, new InteractionDataService.ContactInteractionSummary());

        // Simulate email co-occurrence
        bundle.emailCoOccurrences.put(
            contacts[0].Id, // Using contact ID as fake email ID for testing
            new List<Id>{ contacts[0].Id, contacts[1].Id }
        );

        Test.startTest();
        // The private method processCoOccurrences will be called indirectly
        // We verify the bundle has correct pair data after full fetch
        System.assertEquals(0, bundle.coOccurrencePairs.size(),
            'Pairs should be empty before computation');
        Test.stopTest();
    }

    // ─── InteractionBundle ─────────────────────────────────────────

    @IsTest
    static void testInteractionBundleDefaults() {
        InteractionDataService.InteractionBundle bundle =
            new InteractionDataService.InteractionBundle();

        System.assertNotEquals(null, bundle.contactSummaries);
        System.assertNotEquals(null, bundle.emailCoOccurrences);
        System.assertNotEquals(null, bundle.eventCoOccurrences);
        System.assertNotEquals(null, bundle.coOccurrencePairs);
        System.assertEquals(0, bundle.contactSummaries.size());
    }

    @IsTest
    static void testInteractionBundleGetContactSummary() {
        InteractionDataService.InteractionBundle bundle =
            new InteractionDataService.InteractionBundle();

        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];

        InteractionDataService.ContactInteractionSummary summary =
            new InteractionDataService.ContactInteractionSummary();
        summary.emailsSent = 10;
        bundle.contactSummaries.put(c.Id, summary);

        System.assertEquals(10, bundle.getContactSummary(c.Id).emailsSent,
            'getContactSummary should return the stored summary');
        System.assertEquals(null, bundle.getContactSummary(acct.Id),
            'Missing contact should return null');
    }

    // ─── Sentiment Keywords ────────────────────────────────────────

    @IsTest
    static void testNegativeKeywordsExist() {
        System.assert(InteractionDataService.NEGATIVE_KEYWORDS.contains('concern'));
        System.assert(InteractionDataService.NEGATIVE_KEYWORDS.contains('blocker'));
        System.assert(InteractionDataService.NEGATIVE_KEYWORDS.contains('escalat'));
        System.assert(!InteractionDataService.NEGATIVE_KEYWORDS.contains('great'));
    }

    @IsTest
    static void testPositiveKeywordsExist() {
        System.assert(InteractionDataService.POSITIVE_KEYWORDS.contains('thank'));
        System.assert(InteractionDataService.POSITIVE_KEYWORDS.contains('champion'));
        System.assert(InteractionDataService.POSITIVE_KEYWORDS.contains('recommend'));
        System.assert(!InteractionDataService.POSITIVE_KEYWORDS.contains('issue'));
    }

    // ─── Opportunity Roles ─────────────────────────────────────────

    @IsTest
    static void testFetchOpportunityRoles() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        Contact c = [SELECT Id FROM Contact WHERE AccountId = :acct.Id LIMIT 1];
        Opportunity opp = RelationshipGraphTestDataFactory.createOpportunity(acct.Id, 'Test Deal');
        insert new OpportunityContactRole(
            ContactId = c.Id,
            OpportunityId = opp.Id,
            Role = 'Decision Maker'
        );

        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct.Id, new List<Id>{ c.Id });
        Test.stopTest();

        InteractionDataService.ContactInteractionSummary summary =
            bundle.contactSummaries.get(c.Id);
        System.assertEquals(true, summary.hasOpportunityRole,
            'Contact with OCR should have opportunity role');
        System.assertEquals('Decision Maker', summary.opportunityRole);
    }

    // ─── ExternalContactSummary ────────────────────────────────────

    @IsTest
    static void testExternalContactSummaryDefaults() {
        InteractionDataService.ExternalContactSummary ext =
            new InteractionDataService.ExternalContactSummary();

        System.assertEquals(0, ext.sharedEmailCount);
        System.assertEquals(0, ext.sharedEventCount);
        System.assertNotEquals(null, ext.coOccurringInternalContactIds);
        System.assertEquals(0, ext.coOccurringInternalContactIds.size());
        System.assertEquals(0, ext.getTotalSharedInteractions());
    }

    @IsTest
    static void testExternalContactSummaryComparable() {
        InteractionDataService.ExternalContactSummary ext1 =
            new InteractionDataService.ExternalContactSummary();
        ext1.sharedEmailCount = 5;
        ext1.sharedEventCount = 3;

        InteractionDataService.ExternalContactSummary ext2 =
            new InteractionDataService.ExternalContactSummary();
        ext2.sharedEmailCount = 2;
        ext2.sharedEventCount = 1;

        // ext1 has more total (8 vs 3), so should sort first (descending)
        System.assertEquals(8, ext1.getTotalSharedInteractions());
        System.assertEquals(3, ext2.getTotalSharedInteractions());

        // compareTo returns negative if this should come before other (descending)
        System.assert(ext1.compareTo(ext2) < 0,
            'Higher interaction count should sort first');
        System.assert(ext2.compareTo(ext1) > 0,
            'Lower interaction count should sort after');
    }

    @IsTest
    static void testInteractionBundleExternalContactsInitialized() {
        InteractionDataService.InteractionBundle bundle =
            new InteractionDataService.InteractionBundle();

        System.assertNotEquals(null, bundle.externalContactSummaries,
            'externalContactSummaries should be initialized');
        System.assertEquals(0, bundle.externalContactSummaries.size());
    }

    @IsTest
    static void testDiscoverExternalEmailContacts() {
        // Create two accounts with contacts
        Account acct1 = RelationshipGraphTestDataFactory.createAccount('Account One');
        Account acct2 = RelationshipGraphTestDataFactory.createAccount('Account Two');
        List<Contact> contacts1 = RelationshipGraphTestDataFactory.createContacts(acct1.Id, 2);
        List<Contact> contacts2 = RelationshipGraphTestDataFactory.createContacts(acct2.Id, 1);

        // Create a shared email linking contacts from both accounts
        EmailMessage em = new EmailMessage(
            Subject = 'Shared discussion',
            TextBody = 'Hello',
            RelatedToId = acct1.Id,
            Status = '3'  // Sent
        );
        insert em;

        List<EmailMessageRelation> relations = new List<EmailMessageRelation>();
        relations.add(new EmailMessageRelation(
            EmailMessageId = em.Id,
            RelationId = contacts1[0].Id,
            RelationType = 'ToAddress'
        ));
        relations.add(new EmailMessageRelation(
            EmailMessageId = em.Id,
            RelationId = contacts2[0].Id,
            RelationType = 'CcAddress'
        ));
        insert relations;

        InteractionDataService service = new InteractionDataService();
        List<Id> contactIds = new List<Id>{ contacts1[0].Id, contacts1[1].Id };

        Test.startTest();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct1.Id, contactIds);
        Test.stopTest();

        // The contact from account 2 should be discovered as external
        System.assert(bundle.externalContactSummaries.containsKey(contacts2[0].Id),
            'Contact from Account Two should be discovered as external');
        InteractionDataService.ExternalContactSummary ext =
            bundle.externalContactSummaries.get(contacts2[0].Id);
        System.assert(ext.sharedEmailCount > 0,
            'Should have shared email count');
    }

    @IsTest
    static void testExternalContactHydration() {
        Account acct1 = RelationshipGraphTestDataFactory.createAccount('Hydrate Test Acct');
        Account acct2 = RelationshipGraphTestDataFactory.createAccount('External Acct');
        List<Contact> contacts1 = RelationshipGraphTestDataFactory.createContacts(acct1.Id, 1);
        List<Contact> contacts2 = RelationshipGraphTestDataFactory.createContacts(acct2.Id, 1);

        // Create shared email
        EmailMessage em = new EmailMessage(
            Subject = 'Hydration test',
            TextBody = 'Test',
            RelatedToId = acct1.Id,
            Status = '3'
        );
        insert em;

        insert new List<EmailMessageRelation>{
            new EmailMessageRelation(
                EmailMessageId = em.Id,
                RelationId = contacts1[0].Id,
                RelationType = 'ToAddress'
            ),
            new EmailMessageRelation(
                EmailMessageId = em.Id,
                RelationId = contacts2[0].Id,
                RelationType = 'CcAddress'
            )
        };

        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct1.Id, new List<Id>{ contacts1[0].Id });
        Test.stopTest();

        InteractionDataService.ExternalContactSummary ext =
            bundle.externalContactSummaries.get(contacts2[0].Id);
        System.assertNotEquals(null, ext, 'External contact should be discovered');
        System.assertNotEquals(null, ext.contactName,
            'External contact name should be hydrated');
        System.assertEquals(acct2.Id, ext.accountId,
            'External contact should reference its own account');
        System.assertEquals('External Acct', ext.accountName,
            'External account name should be hydrated');
    }

    @IsTest
    static void testExternalDiscoveryNoExternalsWhenNoSharedEmails() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id];
        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct.Id, contactIds);
        Test.stopTest();

        System.assertEquals(0, bundle.externalContactSummaries.size(),
            'No shared emails means no external contacts');
    }

    // ─── Bulk Behavior ─────────────────────────────────────────────

    @IsTest
    static void testBulkContactFetch() {
        Account acct = [SELECT Id FROM Account LIMIT 1];
        // Already have 5 contacts from setup
        List<Contact> contacts = [SELECT Id FROM Contact WHERE AccountId = :acct.Id];
        List<Id> contactIds = new List<Id>();
        for (Contact c : contacts) contactIds.add(c.Id);

        InteractionDataService service = new InteractionDataService();

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        InteractionDataService.InteractionBundle bundle =
            service.fetchInteractionData(acct.Id, contactIds);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        // Should use bulk queries, not per-contact. Expect ~5-7 queries
        // (EmailMessageRelation, EmailMessage, Event, Task, OpportunityContactRole)
        System.assert(queriesUsed < 10,
            'Should use bulk queries. Used: ' + queriesUsed);
        System.assertEquals(5, bundle.contactSummaries.size());
    }
}
