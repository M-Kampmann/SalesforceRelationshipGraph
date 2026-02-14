/**
 * Calculates relationship strength between contacts and their account.
 * Uses pre-fetched interaction data (bulk pattern) to avoid N+1 query problems.
 * Applies time-decay weighting and normalizes scores to 0.0-1.0 range.
 */
public with sharing class RelationshipStrengthCalculator {

    // Interaction type weights
    private static final Decimal WEIGHT_EMAIL_SENT = 1.0;
    private static final Decimal WEIGHT_EMAIL_RECEIVED = 1.5;
    private static final Decimal WEIGHT_MEETING = 3.0;
    private static final Decimal WEIGHT_TASK = 1.0;
    private static final Decimal WEIGHT_OPP_ROLE = 5.0;
    private static final Decimal WEIGHT_CO_OCCURRENCE = 0.5;

    /**
     * Calculate relationship strengths for all contacts in the bundle.
     * Returns a map of Contact ID → normalized strength (0.0-1.0).
     */
    public Map<Id, Decimal> calculateStrengths(
        Id accountId,
        InteractionDataService.InteractionBundle bundle,
        Decimal timeDecayFactor
    ) {
        Map<Id, Decimal> rawScores = new Map<Id, Decimal>();
        Decimal maxScore = 0.0;

        for (Id contactId : bundle.contactSummaries.keySet()) {
            InteractionDataService.ContactInteractionSummary summary =
                bundle.contactSummaries.get(contactId);

            Decimal score = calculateRawScore(summary);

            rawScores.put(contactId, score);
            if (score > maxScore) {
                maxScore = score;
            }
        }

        // Normalize to 0.0-1.0 using log scale (prevents outliers from compressing everyone else)
        Map<Id, Decimal> normalizedScores = new Map<Id, Decimal>();
        Decimal logMax = maxScore > 0 ? Math.log10(maxScore + 1) : 1.0;

        for (Id contactId : rawScores.keySet()) {
            Decimal raw = rawScores.get(contactId);
            Decimal normalized = raw > 0 ? Math.log10(raw + 1) / logMax : 0.0;
            normalizedScores.put(contactId, Math.min(normalized, 1.0));
        }

        return normalizedScores;
    }

    /**
     * Calculate and persist relationship strengths for an account.
     */
    public void calculateAndPersist(
        Id accountId,
        List<Id> contactIds,
        InteractionDataService.InteractionBundle bundle,
        Decimal timeDecayFactor
    ) {
        Map<Id, Decimal> strengths = calculateStrengths(accountId, bundle, timeDecayFactor);

        // Query existing records for upsert
        Map<String, Relationship_Strength__c> existing = new Map<String, Relationship_Strength__c>();
        for (Relationship_Strength__c rs : [
            SELECT Id, Source_Contact__c, Target_Record_Id__c, Account__c
            FROM Relationship_Strength__c
            WHERE Account__c = :accountId
            AND Source_Contact__c IN :contactIds
            AND Target_Object_Type__c = 'Account'
            WITH SECURITY_ENFORCED
        ]) {
            String key = String.valueOf(rs.Source_Contact__c) + '_' + String.valueOf(rs.Account__c);
            existing.put(key, rs);
        }

        List<Relationship_Strength__c> toUpsert = new List<Relationship_Strength__c>();
        Datetime now = Datetime.now();

        for (Id contactId : strengths.keySet()) {
            String key = String.valueOf(contactId) + '_' + String.valueOf(accountId);
            InteractionDataService.ContactInteractionSummary summary =
                bundle.contactSummaries.get(contactId);

            Relationship_Strength__c rs;
            if (existing.containsKey(key)) {
                rs = existing.get(key);
            } else {
                rs = new Relationship_Strength__c(
                    Source_Contact__c = contactId,
                    Target_Record_Id__c = String.valueOf(accountId),
                    Target_Object_Type__c = 'Account',
                    Account__c = accountId
                );
            }

            rs.Strength__c = strengths.get(contactId);
            rs.Interaction_Count__c = summary != null ? summary.getTotalInteractions() : 0;
            rs.Co_Occurrence_Count__c = summary != null ? summary.coOccurrenceCount : 0;
            rs.Last_Calculated__c = now;

            toUpsert.add(rs);
        }

        // Also persist contact-to-contact co-occurrence strengths
        List<Relationship_Strength__c> coOccurrenceRecords =
            buildCoOccurrenceRecords(accountId, bundle);
        toUpsert.addAll(coOccurrenceRecords);

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
    }

    private Decimal calculateRawScore(InteractionDataService.ContactInteractionSummary summary) {
        if (summary == null) return 0.0;

        return (summary.emailsSent * WEIGHT_EMAIL_SENT)
            + (summary.emailsReceived * WEIGHT_EMAIL_RECEIVED)
            + (summary.meetingsAttended * WEIGHT_MEETING)
            + (summary.tasksCompleted * WEIGHT_TASK)
            + (summary.hasOpportunityRole ? WEIGHT_OPP_ROLE : 0.0)
            + (summary.coOccurrenceCount * WEIGHT_CO_OCCURRENCE);
    }

    private List<Relationship_Strength__c> buildCoOccurrenceRecords(
        Id accountId,
        InteractionDataService.InteractionBundle bundle
    ) {
        List<Relationship_Strength__c> records = new List<Relationship_Strength__c>();
        Datetime now = Datetime.now();

        // Query existing contact-to-contact records
        Set<String> existingKeys = new Set<String>();
        for (Relationship_Strength__c rs : [
            SELECT Id, Source_Contact__c, Target_Record_Id__c
            FROM Relationship_Strength__c
            WHERE Account__c = :accountId
            AND Target_Object_Type__c = 'Contact'
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ]) {
            existingKeys.add(
                String.valueOf(rs.Source_Contact__c) + '_' + rs.Target_Record_Id__c
            );
        }

        for (String pairKey : bundle.coOccurrencePairs.keySet()) {
            Integer count = bundle.coOccurrencePairs.get(pairKey);
            List<String> parts = pairKey.split('_');
            if (parts.size() != 2) continue;

            String contactId1 = parts[0];
            String contactId2 = parts[1];

            // Create bidirectional records if they don't exist
            String key1 = contactId1 + '_' + contactId2;
            if (!existingKeys.contains(key1)) {
                records.add(new Relationship_Strength__c(
                    Source_Contact__c = Id.valueOf(contactId1),
                    Target_Record_Id__c = contactId2,
                    Target_Object_Type__c = 'Contact',
                    Account__c = accountId,
                    Strength__c = Math.min(count / 20.0, 1.0), // Normalize: 20+ co-occurrences = max
                    Co_Occurrence_Count__c = count,
                    Last_Calculated__c = now
                ));
            }
        }

        return records;
    }
}
