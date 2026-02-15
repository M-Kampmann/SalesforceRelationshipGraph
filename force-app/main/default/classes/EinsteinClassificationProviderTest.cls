/**
 * Unit tests for EinsteinClassificationProvider.
 * Uses HttpCalloutMock to simulate Einstein Models API responses.
 */
@IsTest
private class EinsteinClassificationProviderTest {

    // ─── Mock Classes ────────────────────────────────────────────────

    private class EinsteinSuccessMock implements HttpCalloutMock {
        private String generatedText;

        public EinsteinSuccessMock(String generatedText) {
            this.generatedText = generatedText;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"generation":{"generatedText":' +
                JSON.serialize(generatedText) + '}}');
            return res;
        }
    }

    private class EinsteinErrorMock implements HttpCalloutMock {
        private Integer statusCode;

        public EinsteinErrorMock(Integer statusCode) {
            this.statusCode = statusCode;
        }

        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(statusCode);
            res.setBody('{"error":"Service unavailable"}');
            return res;
        }
    }

    private class EinsteinMalformedMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"generation":{"generatedText":"not valid json at all"}}');
            return res;
        }
    }

    // ─── Helper ──────────────────────────────────────────────────────

    private static InteractionDataService.InteractionBundle createBundle(
        List<Contact> contacts
    ) {
        return RelationshipGraphTestDataFactory.createInteractionBundle(contacts);
    }

    // ─── Tests ───────────────────────────────────────────────────────

    @IsTest
    static void testClassifyContactsSuccess() {
        Account a = RelationshipGraphTestDataFactory.createAccount('Einstein Test');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(a.Id, 2);
        InteractionDataService.InteractionBundle bundle = createBundle(contacts);

        // Build mock response with valid classifications
        String jsonResponse = '{"classifications":['
            + '{"contactId":"' + contacts[0].Id + '","classification":"Champion","confidenceScore":0.9},'
            + '{"contactId":"' + contacts[1].Id + '","classification":"Economic Buyer","confidenceScore":0.8}'
            + ']}';

        Test.setMock(HttpCalloutMock.class, new EinsteinSuccessMock(jsonResponse));

        Test.startTest();
        EinsteinClassificationProvider provider = new EinsteinClassificationProvider();
        List<Id> contactIds = new List<Id>{ contacts[0].Id, contacts[1].Id };
        Map<Id, ClassificationResult> results =
            provider.classifyContacts(a.Id, contactIds, bundle);
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should have 2 classifications');
        System.assertEquals('Champion', results.get(contacts[0].Id).classification);
        System.assertEquals(0.9, results.get(contacts[0].Id).confidenceScore);
        System.assertEquals('Economic Buyer', results.get(contacts[1].Id).classification);
        System.assertEquals('EinsteinClassificationProvider',
            results.get(contacts[0].Id).providerName);
    }

    @IsTest
    static void testClassifyContactsApiError() {
        Account a = RelationshipGraphTestDataFactory.createAccount('Einstein Error Test');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(a.Id, 1);
        InteractionDataService.InteractionBundle bundle = createBundle(contacts);

        Test.setMock(HttpCalloutMock.class, new EinsteinErrorMock(500));

        Test.startTest();
        EinsteinClassificationProvider provider = new EinsteinClassificationProvider();
        Map<Id, ClassificationResult> results =
            provider.classifyContacts(a.Id, new List<Id>{ contacts[0].Id }, bundle);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty map on API error');
    }

    @IsTest
    static void testClassifyContactsMalformedResponse() {
        Account a = RelationshipGraphTestDataFactory.createAccount('Einstein Malformed Test');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(a.Id, 1);
        InteractionDataService.InteractionBundle bundle = createBundle(contacts);

        Test.setMock(HttpCalloutMock.class, new EinsteinMalformedMock());

        Test.startTest();
        EinsteinClassificationProvider provider = new EinsteinClassificationProvider();
        Map<Id, ClassificationResult> results =
            provider.classifyContacts(a.Id, new List<Id>{ contacts[0].Id }, bundle);
        Test.stopTest();

        System.assertEquals(0, results.size(), 'Should return empty map on malformed JSON');
    }

    @IsTest
    static void testIsAvailableTrue() {
        Test.setMock(HttpCalloutMock.class, new EinsteinSuccessMock('Hello'));

        Test.startTest();
        EinsteinClassificationProvider provider = new EinsteinClassificationProvider();
        Boolean available = provider.isAvailable();
        Test.stopTest();

        System.assertEquals(true, available, 'Should be available when API returns 200');
    }

    @IsTest
    static void testIsAvailableFalse() {
        Test.setMock(HttpCalloutMock.class, new EinsteinErrorMock(500));

        Test.startTest();
        EinsteinClassificationProvider provider = new EinsteinClassificationProvider();
        Boolean available = provider.isAvailable();
        Test.stopTest();

        System.assertEquals(false, available, 'Should be unavailable when API returns 500');
    }

    @IsTest
    static void testBuildPromptContainsContactData() {
        Account a = RelationshipGraphTestDataFactory.createAccount('Prompt Test');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(a.Id, 2);

        Map<Id, Contact> contactMap = new Map<Id, Contact>([
            SELECT Id, Name, Title FROM Contact WHERE Id IN :contacts
        ]);

        InteractionDataService.InteractionBundle bundle = createBundle(contacts);
        // Set some interaction data
        InteractionDataService.ContactInteractionSummary summary =
            bundle.contactSummaries.get(contacts[0].Id);
        summary.emailsSent = 5;
        summary.meetingsAttended = 3;

        Test.startTest();
        EinsteinClassificationProvider provider = new EinsteinClassificationProvider();
        String prompt = provider.buildPrompt(
            a.Id, new List<Id>{ contacts[0].Id, contacts[1].Id },
            contactMap, bundle
        );
        Test.stopTest();

        System.assert(prompt.contains(String.valueOf(contacts[0].Id)),
            'Prompt should contain contact ID');
        System.assert(prompt.contains('5 emails sent'),
            'Prompt should contain email count');
        System.assert(prompt.contains('3 meetings'),
            'Prompt should contain meeting count');
        System.assert(prompt.contains('Champion'),
            'Prompt should list valid classifications');
    }

    @IsTest
    static void testParseResponseFiltersInvalidClassifications() {
        Account a = RelationshipGraphTestDataFactory.createAccount('Parse Filter Test');
        List<Contact> contacts = RelationshipGraphTestDataFactory.createContacts(a.Id, 2);

        // One valid, one invalid classification
        String jsonResponse = '{"classifications":['
            + '{"contactId":"' + contacts[0].Id + '","classification":"Champion","confidenceScore":0.9},'
            + '{"contactId":"' + contacts[1].Id + '","classification":"InvalidRole","confidenceScore":0.8}'
            + ']}';

        String einsteinResponse = '{"generation":{"generatedText":'
            + JSON.serialize(jsonResponse) + '}}';

        Test.startTest();
        EinsteinClassificationProvider provider = new EinsteinClassificationProvider();
        Map<Id, ClassificationResult> results = provider.parseEinsteinResponse(
            einsteinResponse,
            new List<Id>{ contacts[0].Id, contacts[1].Id }
        );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should only have 1 valid classification');
        System.assert(results.containsKey(contacts[0].Id), 'Should contain valid contact');
        System.assert(!results.containsKey(contacts[1].Id), 'Should filter out invalid');
    }

    @IsTest
    static void testFactoryFallbackWhenUnavailable() {
        // Einstein returns 500 → factory should fall back to Heuristic
        Test.setMock(HttpCalloutMock.class, new EinsteinErrorMock(500));

        Test.startTest();
        IClassificationProvider provider = ClassificationProviderFactory.getProvider();
        Test.stopTest();

        System.assertEquals('HeuristicClassificationProvider', provider.getProviderName(),
            'Should fall back to Heuristic when Einstein is unavailable');
    }

    @IsTest
    static void testGetProviderName() {
        EinsteinClassificationProvider provider = new EinsteinClassificationProvider();
        System.assertEquals('EinsteinClassificationProvider', provider.getProviderName());
    }
}
