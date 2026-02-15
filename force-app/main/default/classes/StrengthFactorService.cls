/**
 * Reads and caches Strength_Factor__mdt records.
 * Provides the list of active factors and maps interaction source values
 * to ContactInteractionSummary fields.
 */
public with sharing class StrengthFactorService {

    private static List<Strength_Factor__mdt> cachedFactors;

    /**
     * Wrapper for a single strength factor configuration.
     */
    public class StrengthFactor {
        @AuraEnabled public String developerName { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public Decimal weight { get; set; }
        @AuraEnabled public String sourceType { get; set; }
        @AuraEnabled public String sourceValue { get; set; }
        @AuraEnabled public Decimal maxValue { get; set; }
        @AuraEnabled public String category { get; set; }
    }

    /**
     * Return all active Strength_Factor__mdt records as StrengthFactor wrappers.
     * Falls back to hardcoded defaults if no CMT records exist.
     */
    public static List<StrengthFactor> getActiveFactors() {
        if (cachedFactors == null) {
            cachedFactors = [
                SELECT DeveloperName, Label, Weight__c, Source_Type__c,
                       Source_Value__c, Max_Value__c, Is_Active__c, Category__c
                FROM Strength_Factor__mdt
                WHERE Is_Active__c = true
                ORDER BY Category__c, DeveloperName
            ];
        }

        if (cachedFactors.isEmpty()) {
            return getHardcodedDefaults();
        }

        List<StrengthFactor> factors = new List<StrengthFactor>();
        for (Strength_Factor__mdt mdt : cachedFactors) {
            factors.add(fromMetadata(mdt));
        }
        return factors;
    }

    /**
     * Given a ContactInteractionSummary and a source value key,
     * return the numeric value for an Interaction-type factor.
     */
    public static Decimal getInteractionValue(
        InteractionDataService.ContactInteractionSummary summary,
        String sourceValue
    ) {
        if (summary == null) return 0;
        switch on sourceValue {
            when 'email_sent' { return summary.emailsSent; }
            when 'email_received' { return summary.emailsReceived; }
            when 'meeting' { return summary.meetingsAttended; }
            when 'task' { return summary.tasksCompleted; }
            when 'opp_role' { return summary.hasOpportunityRole ? 1.0 : 0.0; }
            when 'co_occurrence' { return summary.coOccurrenceCount; }
            when else { return 0; }
        }
    }

    /**
     * Hardcoded fallback matching original RelationshipStrengthCalculator weights.
     * Used when no Strength_Factor__mdt records are deployed.
     */
    @TestVisible
    private static List<StrengthFactor> getHardcodedDefaults() {
        List<StrengthFactor> defaults = new List<StrengthFactor>();
        defaults.add(buildDefault('Email_Sent', 'Email Sent', 1.0, 'email_sent', 'Activity'));
        defaults.add(buildDefault('Email_Received', 'Email Received', 1.5, 'email_received', 'Activity'));
        defaults.add(buildDefault('Meeting', 'Meeting', 3.0, 'meeting', 'Activity'));
        defaults.add(buildDefault('Task', 'Task', 1.0, 'task', 'Activity'));
        defaults.add(buildDefault('Opportunity_Role', 'Opportunity Role', 5.0, 'opp_role', 'Activity'));
        defaults.add(buildDefault('Co_Occurrence', 'Co-Occurrence', 0.5, 'co_occurrence', 'Activity'));
        return defaults;
    }

    private static StrengthFactor buildDefault(
        String devName, String lbl, Decimal weight, String sourceValue, String category
    ) {
        StrengthFactor f = new StrengthFactor();
        f.developerName = devName;
        f.label = lbl;
        f.weight = weight;
        f.sourceType = 'Interaction';
        f.sourceValue = sourceValue;
        f.maxValue = null;
        f.category = category;
        return f;
    }

    private static StrengthFactor fromMetadata(Strength_Factor__mdt mdt) {
        StrengthFactor f = new StrengthFactor();
        f.developerName = mdt.DeveloperName;
        f.label = mdt.Label;
        f.weight = mdt.Weight__c;
        f.sourceType = mdt.Source_Type__c;
        f.sourceValue = mdt.Source_Value__c;
        f.maxValue = mdt.Max_Value__c;
        f.category = mdt.Category__c;
        return f;
    }

    @TestVisible
    private static void clearCache() {
        cachedFactors = null;
    }
}
