/**
 * Agentforce-powered contact classification provider.
 * Uses Salesforce Agentforce API for AI-based contact role classification.
 * Falls back gracefully if Agentforce is unavailable.
 */
public with sharing class AgentforceClassificationProvider implements IClassificationProvider {

    private static final String AGENT_API_ENDPOINT = '/services/data/v62.0/einstein/ai-agents';

    public Map<Id, ClassificationResult> classifyContacts(
        Id accountId,
        List<Id> contactIds,
        InteractionDataService.InteractionBundle interactionData
    ) {
        Map<Id, ClassificationResult> results = new Map<Id, ClassificationResult>();

        // Build the prompt context from interaction data
        String promptContext = buildPromptContext(accountId, contactIds, interactionData);

        try {
            // Call Agentforce API
            String responseBody = callAgentforce(promptContext);
            results = parseAgentforceResponse(responseBody, contactIds);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Agentforce classification failed: ' + e.getMessage());
            // Return empty map — caller should fall back to heuristic
            return results;
        }

        return results;
    }

    public String getProviderName() {
        return 'AgentforceClassificationProvider';
    }

    public Boolean isAvailable() {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + AGENT_API_ENDPOINT);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
            req.setHeader('Content-Type', 'application/json');
            req.setTimeout(5000);

            HttpResponse res = new Http().send(req);
            return res.getStatusCode() == 200;
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'Agentforce availability check failed: ' + e.getMessage());
            return false;
        }
    }

    @TestVisible
    private String buildPromptContext(
        Id accountId,
        List<Id> contactIds,
        InteractionDataService.InteractionBundle interactionData
    ) {
        JSONGenerator gen = JSON.createGenerator(false);
        gen.writeStartObject();
        gen.writeStringField('accountId', accountId);
        gen.writeFieldName('contacts');
        gen.writeStartArray();

        for (Id contactId : contactIds) {
            InteractionDataService.ContactInteractionSummary summary =
                interactionData.getContactSummary(contactId);

            gen.writeStartObject();
            gen.writeStringField('contactId', contactId);
            if (summary != null) {
                gen.writeNumberField('emailsSent', summary.emailsSent);
                gen.writeNumberField('emailsReceived', summary.emailsReceived);
                gen.writeNumberField('meetingsAttended', summary.meetingsAttended);
                gen.writeNumberField('tasksCompleted', summary.tasksCompleted);
                gen.writeNumberField('coOccurrenceCount', summary.coOccurrenceCount);
                gen.writeBooleanField('hasOpportunityRole', summary.hasOpportunityRole);
                if (summary.hasOpportunityRole) {
                    gen.writeStringField('opportunityRole', summary.opportunityRole);
                }
            }
            gen.writeEndObject();
        }

        gen.writeEndArray();
        gen.writeStringField('instruction',
            'Classify each contact into one of: Champion, Economic Buyer, Technical Buyer, ' +
            'Blocker, Influencer, End User, Detractor, Unknown. ' +
            'Return a JSON array with objects containing contactId, classification, and confidenceScore (0.0-1.0). ' +
            'Base classifications on interaction patterns, engagement levels, and role signals.'
        );
        gen.writeEndObject();

        return gen.getAsString();
    }

    private String callAgentforce(String promptContext) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + AGENT_API_ENDPOINT + '/classify');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(30000);
        req.setBody(promptContext);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            throw new AgentforceException(
                'Agentforce API returned status ' + res.getStatusCode() + ': ' + res.getBody()
            );
        }

        return res.getBody();
    }

    @TestVisible
    private Map<Id, ClassificationResult> parseAgentforceResponse(
        String responseBody,
        List<Id> contactIds
    ) {
        Map<Id, ClassificationResult> results = new Map<Id, ClassificationResult>();
        Set<Id> contactIdSet = new Set<Id>(contactIds);

        try {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(responseBody);
            List<Object> classifications = (List<Object>) responseMap.get('classifications');

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
            System.debug(LoggingLevel.ERROR, 'Failed to parse Agentforce response: ' + e.getMessage());
        }

        return results;
    }

    public class AgentforceException extends Exception {}
}
