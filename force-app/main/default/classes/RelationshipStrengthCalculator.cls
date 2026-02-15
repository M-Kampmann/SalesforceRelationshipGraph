/**
 * Calculates relationship strength between contacts and their account.
 * Uses pre-fetched interaction data (bulk pattern) to avoid N+1 query problems.
 * Reads configurable factor weights from Strength_Factor__mdt.
 * Applies time-decay weighting and normalizes scores to 0.0-1.0 range.
 */
public with sharing class RelationshipStrengthCalculator {

    /**
     * Factor breakdown entry for a single factor's contribution to the score.
     * Serialized to JSON and stored in Strength_Breakdown__c for the LWC detail panel.
     */
    public class FactorBreakdown {
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String category { get; set; }
        @AuraEnabled public Decimal rawValue { get; set; }
        @AuraEnabled public Decimal weight { get; set; }
        @AuraEnabled public Decimal contribution { get; set; }
    }

    /**
     * Calculate relationship strengths for all contacts in the bundle.
     * Returns a map of Contact ID to normalized strength (0.0-1.0).
     */
    public Map<Id, Decimal> calculateStrengths(
        Id accountId,
        InteractionDataService.InteractionBundle bundle,
        Decimal timeDecayFactor
    ) {
        List<StrengthFactorService.StrengthFactor> factors =
            StrengthFactorService.getActiveFactors();

        Map<Id, Decimal> rawScores = new Map<Id, Decimal>();
        Decimal maxScore = 0.0;

        Decimal decay = (timeDecayFactor != null && timeDecayFactor > 0 && timeDecayFactor < 1)
            ? timeDecayFactor : 1.0;

        for (Id contactId : bundle.contactSummaries.keySet()) {
            InteractionDataService.ContactInteractionSummary summary =
                bundle.contactSummaries.get(contactId);

            Decimal score = calculateRawScore(summary, factors);

            // Apply time decay: score * decay^(weeks since last interaction)
            if (decay < 1.0 && summary != null && summary.lastInteractionDate != null) {
                Long daysSince = summary.lastInteractionDate.daysBetween(Date.today());
                Decimal weeksSince = daysSince / 7.0;
                Decimal decayMultiplier = 1.0;
                Integer fullWeeks = Integer.valueOf(weeksSince);
                for (Integer w = 0; w < Math.min(fullWeeks, 52); w++) {
                    decayMultiplier *= decay;
                }
                score *= decayMultiplier;
            }

            rawScores.put(contactId, score);
            if (score > maxScore) {
                maxScore = score;
            }
        }

        // Normalize to 0.0-1.0 using log scale
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
        List<StrengthFactorService.StrengthFactor> factors =
            StrengthFactorService.getActiveFactors();

        Map<Id, Decimal> strengths = calculateStrengths(accountId, bundle, timeDecayFactor);

        // Build factor breakdowns per contact
        Map<Id, List<FactorBreakdown>> breakdowns = new Map<Id, List<FactorBreakdown>>();
        for (Id contactId : strengths.keySet()) {
            InteractionDataService.ContactInteractionSummary summary =
                bundle.contactSummaries.get(contactId);
            breakdowns.put(contactId, buildFactorBreakdown(summary, factors));
        }

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

            List<FactorBreakdown> breakdown = breakdowns.get(contactId);
            rs.Strength_Reason__c = generateStrengthReason(summary, strengths.get(contactId), breakdown);
            rs.Strength_Breakdown__c = JSON.serialize(breakdown);

            toUpsert.add(rs);
        }

        // Also persist contact-to-contact co-occurrence strengths
        List<Relationship_Strength__c> coOccurrenceRecords =
            buildCoOccurrenceRecords(accountId, bundle);
        toUpsert.addAll(coOccurrenceRecords);

        if (!toUpsert.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPSERTABLE, toUpsert
            );
            upsert decision.getRecords();
        }
    }

    /**
     * Calculate raw weighted score from all active factors.
     */
    @TestVisible
    private Decimal calculateRawScore(
        InteractionDataService.ContactInteractionSummary summary,
        List<StrengthFactorService.StrengthFactor> factors
    ) {
        if (summary == null) return 0.0;

        Decimal total = 0.0;
        for (StrengthFactorService.StrengthFactor factor : factors) {
            Decimal rawValue = getFactorValue(summary, factor);

            // Normalize if Max_Value is set
            if (factor.maxValue != null && factor.maxValue > 0) {
                rawValue = Math.min(rawValue / factor.maxValue, 1.0);
            }

            total += rawValue * factor.weight;
        }

        return total;
    }

    /**
     * Build per-factor breakdown for a contact.
     */
    private List<FactorBreakdown> buildFactorBreakdown(
        InteractionDataService.ContactInteractionSummary summary,
        List<StrengthFactorService.StrengthFactor> factors
    ) {
        List<FactorBreakdown> breakdown = new List<FactorBreakdown>();
        if (summary == null) return breakdown;

        for (StrengthFactorService.StrengthFactor factor : factors) {
            Decimal rawValue = getFactorValue(summary, factor);
            if (rawValue == 0) continue;

            Decimal normalizedValue = rawValue;
            if (factor.maxValue != null && factor.maxValue > 0) {
                normalizedValue = Math.min(rawValue / factor.maxValue, 1.0);
            }

            FactorBreakdown fb = new FactorBreakdown();
            fb.name = factor.label;
            fb.category = factor.category;
            fb.rawValue = rawValue;
            fb.weight = factor.weight;
            fb.contribution = normalizedValue * factor.weight;
            breakdown.add(fb);
        }

        return breakdown;
    }

    /**
     * Get the raw numeric value for a factor from the contact summary.
     */
    private Decimal getFactorValue(
        InteractionDataService.ContactInteractionSummary summary,
        StrengthFactorService.StrengthFactor factor
    ) {
        if (factor.sourceType == 'Interaction') {
            return StrengthFactorService.getInteractionValue(summary, factor.sourceValue);
        }
        // Contact_Field or Record_Count — look up from customFactors map
        if (summary.customFactors != null && summary.customFactors.containsKey(factor.developerName)) {
            return summary.customFactors.get(factor.developerName);
        }
        return 0;
    }

    private List<Relationship_Strength__c> buildCoOccurrenceRecords(
        Id accountId,
        InteractionDataService.InteractionBundle bundle
    ) {
        List<Relationship_Strength__c> records = new List<Relationship_Strength__c>();
        Datetime now = Datetime.now();

        Map<String, Relationship_Strength__c> existingMap = new Map<String, Relationship_Strength__c>();
        for (Relationship_Strength__c rs : [
            SELECT Id, Source_Contact__c, Target_Record_Id__c, Strength__c, Co_Occurrence_Count__c
            FROM Relationship_Strength__c
            WHERE Account__c = :accountId
            AND Target_Object_Type__c = 'Contact'
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ]) {
            existingMap.put(
                String.valueOf(rs.Source_Contact__c) + '_' + rs.Target_Record_Id__c, rs
            );
        }

        for (String pairKey : bundle.coOccurrencePairs.keySet()) {
            Integer count = bundle.coOccurrencePairs.get(pairKey);
            List<String> parts = pairKey.split('_');
            if (parts.size() != 2) continue;

            String contactId1 = parts[0];
            String contactId2 = parts[1];
            String key1 = contactId1 + '_' + contactId2;

            Relationship_Strength__c rs;
            if (existingMap.containsKey(key1)) {
                rs = existingMap.get(key1);
            } else {
                rs = new Relationship_Strength__c(
                    Source_Contact__c = Id.valueOf(contactId1),
                    Target_Record_Id__c = contactId2,
                    Target_Object_Type__c = 'Contact',
                    Account__c = accountId
                );
            }
            rs.Strength__c = Math.min(count / 20.0, 1.0);
            rs.Co_Occurrence_Count__c = count;
            rs.Last_Calculated__c = now;
            records.add(rs);
        }

        return records;
    }

    /**
     * Generate human-readable strength reason from factor breakdown.
     */
    private String generateStrengthReason(
        InteractionDataService.ContactInteractionSummary summary,
        Decimal normalizedStrength,
        List<FactorBreakdown> breakdown
    ) {
        if (summary == null) return null;

        // Engagement level label
        String level;
        if (normalizedStrength >= 0.7) {
            level = 'Strong engagement';
        } else if (normalizedStrength >= 0.4) {
            level = 'Moderate engagement';
        } else if (normalizedStrength > 0) {
            level = 'Low engagement';
        } else {
            return 'No recorded interactions.';
        }

        List<String> parts = new List<String>();

        // Built-in interaction descriptions (preserve existing wording)
        Integer totalEmails = summary.emailsSent + summary.emailsReceived;
        if (totalEmails > 0) {
            parts.add(totalEmails + ' email' + (totalEmails != 1 ? 's' : '') + ' exchanged');
        }
        if (summary.meetingsAttended > 0) {
            parts.add(summary.meetingsAttended + ' meeting'
                + (summary.meetingsAttended != 1 ? 's' : '') + ' attended');
        }
        if (summary.tasksCompleted > 0) {
            parts.add(summary.tasksCompleted + ' task'
                + (summary.tasksCompleted != 1 ? 's' : '') + ' completed');
        }
        if (summary.hasOpportunityRole && String.isNotBlank(summary.opportunityRole)) {
            parts.add(summary.opportunityRole + ' on opportunity');
        } else if (summary.hasOpportunityRole) {
            parts.add('has opportunity role');
        }
        if (summary.coOccurrenceCount > 0) {
            parts.add('appeared with ' + summary.coOccurrenceCount
                + ' other contact' + (summary.coOccurrenceCount != 1 ? 's' : ''));
        }

        // Custom factor descriptions
        if (breakdown != null) {
            Set<String> builtInNames = new Set<String>{
                'Email Sent', 'Email Received', 'Meeting', 'Task',
                'Opportunity Role', 'Co-Occurrence'
            };
            for (FactorBreakdown fb : breakdown) {
                if (!builtInNames.contains(fb.name) && fb.rawValue > 0) {
                    String factorText = fb.name + ': ' + fb.rawValue.setScale(1);
                    if (fb.category != null) {
                        factorText += ' (' + fb.category + ')';
                    }
                    parts.add(factorText);
                }
            }
        }

        if (parts.isEmpty()) {
            return level + '.';
        }

        return level + ': ' + String.join(parts, ', ') + '.';
    }
}
