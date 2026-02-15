/**
 * Einstein-powered contact classification provider.
 * Uses the Einstein Models API (prompt completions) for AI-based contact role classification.
 * Falls back gracefully if Einstein is unavailable (caller uses HeuristicClassificationProvider).
 */
public with sharing class EinsteinClassificationProvider implements IClassificationProvider {

    private static final String EINSTEIN_ENDPOINT =
        '/services/data/v62.0/einstein/llm/prompt-completions';

    public Map<Id, ClassificationResult> classifyContacts(
        Id accountId,
        List<Id> contactIds,
        InteractionDataService.InteractionBundle interactionData
    ) {
        Map<Id, ClassificationResult> results = new Map<Id, ClassificationResult>();

        // Fetch contact details for title info in prompt
        Map<Id, Contact> contacts = new Map<Id, Contact>([
            SELECT Id, Name, Title
            FROM Contact
            WHERE Id IN :contactIds
            WITH SECURITY_ENFORCED
        ]);

        String prompt = buildPrompt(accountId, contactIds, contacts, interactionData);

        try {
            String responseBody = callEinstein(prompt);
            results = parseEinsteinResponse(responseBody, contactIds);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Einstein classification failed: ' + e.getMessage());
        }

        return results;
    }

    public String getProviderName() {
        return 'EinsteinClassificationProvider';
    }

    public Boolean isAvailable() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + EINSTEIN_ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(5000);

            // Minimal health-check prompt
            Map<String, Object> body = new Map<String, Object>{
                'promptTextorId' => 'Hello',
                'additionalConfig' => new Map<String, Object>{
                    'maxTokens' => 10,
                    'applicationName' => 'RelationshipGraph'
                }
            };
            req.setBody(JSON.serialize(body));

            HttpResponse res = new Http().send(req);
            return res.getStatusCode() == 200;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN,
                'Einstein availability check failed: ' + e.getMessage());
            return false;
        }
    }

    @TestVisible
    private String buildPrompt(
        Id accountId,
        List<Id> contactIds,
        Map<Id, Contact> contacts,
        InteractionDataService.InteractionBundle interactionData
    ) {
        String prompt = 'You are a Salesforce contact classification expert. '
            + 'Classify each contact into exactly one of these roles based on their '
            + 'interaction data: Champion, Economic Buyer, Technical Buyer, Blocker, '
            + 'Influencer, End User, Detractor, Unknown.\n\n'
            + 'Account: ' + accountId + '\n\nContacts:\n';

        for (Id contactId : contactIds) {
            Contact c = contacts.get(contactId);
            InteractionDataService.ContactInteractionSummary summary =
                interactionData.getContactSummary(contactId);

            String title = (c != null && c.Title != null) ? c.Title : 'N/A';
            String name = (c != null && c.Name != null) ? c.Name : 'Unknown';

            prompt += '- ' + contactId + ': Name=' + name + ', Title=' + title;

            if (summary != null) {
                prompt += ', ' + summary.emailsSent + ' emails sent'
                    + ', ' + summary.emailsReceived + ' received'
                    + ', ' + summary.meetingsAttended + ' meetings'
                    + ', ' + summary.tasksCompleted + ' tasks';
                if (summary.hasOpportunityRole) {
                    prompt += ', opportunity role=' + summary.opportunityRole;
                }
                prompt += ', co-occurred with ' + summary.coOccurrenceCount + ' contacts';
            }
            prompt += '\n';
        }

        prompt += '\nRespond ONLY with a JSON object in this exact format:\n'
            + '{"classifications":[{"contactId":"003...","classification":"Champion",'
            + '"confidenceScore":0.85},...]}';

        return prompt;
    }

    @TestVisible
    private String callEinstein(String prompt) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + EINSTEIN_ENDPOINT);
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000);

        Map<String, Object> body = new Map<String, Object>{
            'promptTextorId' => prompt,
            'additionalConfig' => new Map<String, Object>{
                'maxTokens' => 2048,
                'applicationName' => 'RelationshipGraph'
            }
        };
        req.setBody(JSON.serialize(body));

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            throw new EinsteinClassificationException(
                'Einstein API returned status ' + res.getStatusCode()
                + ': ' + res.getBody()
            );
        }

        return res.getBody();
    }

    @TestVisible
    private Map<Id, ClassificationResult> parseEinsteinResponse(
        String responseBody,
        List<Id> contactIds
    ) {
        Map<Id, ClassificationResult> results = new Map<Id, ClassificationResult>();
        Set<Id> contactIdSet = new Set<Id>(contactIds);

        try {
            // Einstein returns: { "generation": { "generatedText": "..." } }
            Map<String, Object> responseMap =
                (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            Map<String, Object> generation =
                (Map<String, Object>) responseMap.get('generation');

            if (generation == null) {
                return results;
            }

            String generatedText = (String) generation.get('generatedText');
            if (String.isBlank(generatedText)) {
                return results;
            }

            // Parse the generated text as JSON
            Map<String, Object> parsed =
                (Map<String, Object>) JSON.deserializeUntyped(generatedText);
            List<Object> classifications = (List<Object>) parsed.get('classifications');

            if (classifications == null) {
                return results;
            }

            for (Object item : classifications) {
                Map<String, Object> classItem = (Map<String, Object>) item;
                String contactIdStr = (String) classItem.get('contactId');
                String classification = (String) classItem.get('classification');
                Decimal confidence = (Decimal) classItem.get('confidenceScore');

                Id contactId;
                try {
                    contactId = Id.valueOf(contactIdStr);
                } catch (Exception e) {
                    continue;
                }

                if (!contactIdSet.contains(contactId)) {
                    continue;
                }

                ClassificationResult result = new ClassificationResult(
                    classification, confidence, getProviderName()
                );

                if (result.isValid()) {
                    results.put(contactId, result);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Failed to parse Einstein response: ' + e.getMessage());
        }

        return results;
    }

    public class EinsteinClassificationException extends Exception {}
}
