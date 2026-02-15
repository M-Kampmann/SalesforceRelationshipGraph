/**
 * Unit tests for StrengthFactorService.
 * Tests factor loading, interaction value mapping, and fallback defaults.
 */
@IsTest
private class StrengthFactorServiceTest {

    @IsTest
    static void testGetActiveFactorsReturnsCMTRecords() {
        // CMT records are deployed with the project, so they're available in tests
        StrengthFactorService.clearCache();

        Test.startTest();
        List<StrengthFactorService.StrengthFactor> factors =
            StrengthFactorService.getActiveFactors();
        Test.stopTest();

        // Should have at least 6 built-in factors
        System.assert(factors.size() >= 6,
            'Should have at least 6 active factors, got: ' + factors.size());

        // Verify email_sent factor exists with correct weight
        Boolean foundEmailSent = false;
        for (StrengthFactorService.StrengthFactor f : factors) {
            if (f.sourceValue == 'email_sent') {
                foundEmailSent = true;
                System.assertEquals(1.0, f.weight, 'Email Sent weight should be 1.0');
                System.assertEquals('Interaction', f.sourceType);
                System.assertEquals('Activity', f.category);
            }
        }
        System.assert(foundEmailSent, 'Should find email_sent factor');
    }

    @IsTest
    static void testHardcodedFallbackReturns6Defaults() {
        Test.startTest();
        List<StrengthFactorService.StrengthFactor> defaults =
            StrengthFactorService.getHardcodedDefaults();
        Test.stopTest();

        System.assertEquals(6, defaults.size(), 'Should have exactly 6 default factors');

        // Verify weights match original hardcoded values
        Map<String, Decimal> expectedWeights = new Map<String, Decimal>{
            'email_sent' => 1.0,
            'email_received' => 1.5,
            'meeting' => 3.0,
            'task' => 1.0,
            'opp_role' => 5.0,
            'co_occurrence' => 0.5
        };

        for (StrengthFactorService.StrengthFactor f : defaults) {
            System.assert(expectedWeights.containsKey(f.sourceValue),
                'Unexpected factor: ' + f.sourceValue);
            System.assertEquals(expectedWeights.get(f.sourceValue), f.weight,
                'Weight mismatch for ' + f.sourceValue);
            System.assertEquals('Interaction', f.sourceType);
        }
    }

    @IsTest
    static void testGetInteractionValueEmailSent() {
        InteractionDataService.ContactInteractionSummary s =
            new InteractionDataService.ContactInteractionSummary();
        s.emailsSent = 12;
        System.assertEquals(12, StrengthFactorService.getInteractionValue(s, 'email_sent'));
    }

    @IsTest
    static void testGetInteractionValueEmailReceived() {
        InteractionDataService.ContactInteractionSummary s =
            new InteractionDataService.ContactInteractionSummary();
        s.emailsReceived = 8;
        System.assertEquals(8, StrengthFactorService.getInteractionValue(s, 'email_received'));
    }

    @IsTest
    static void testGetInteractionValueMeeting() {
        InteractionDataService.ContactInteractionSummary s =
            new InteractionDataService.ContactInteractionSummary();
        s.meetingsAttended = 5;
        System.assertEquals(5, StrengthFactorService.getInteractionValue(s, 'meeting'));
    }

    @IsTest
    static void testGetInteractionValueTask() {
        InteractionDataService.ContactInteractionSummary s =
            new InteractionDataService.ContactInteractionSummary();
        s.tasksCompleted = 3;
        System.assertEquals(3, StrengthFactorService.getInteractionValue(s, 'task'));
    }

    @IsTest
    static void testGetInteractionValueOppRole() {
        InteractionDataService.ContactInteractionSummary s =
            new InteractionDataService.ContactInteractionSummary();
        s.hasOpportunityRole = true;
        System.assertEquals(1.0, StrengthFactorService.getInteractionValue(s, 'opp_role'));

        s.hasOpportunityRole = false;
        System.assertEquals(0.0, StrengthFactorService.getInteractionValue(s, 'opp_role'));
    }

    @IsTest
    static void testGetInteractionValueCoOccurrence() {
        InteractionDataService.ContactInteractionSummary s =
            new InteractionDataService.ContactInteractionSummary();
        s.coOccurrenceCount = 7;
        System.assertEquals(7, StrengthFactorService.getInteractionValue(s, 'co_occurrence'));
    }

    @IsTest
    static void testGetInteractionValueNullSummary() {
        System.assertEquals(0, StrengthFactorService.getInteractionValue(null, 'email_sent'));
    }

    @IsTest
    static void testGetInteractionValueUnknownKey() {
        InteractionDataService.ContactInteractionSummary s =
            new InteractionDataService.ContactInteractionSummary();
        s.emailsSent = 10;
        System.assertEquals(0, StrengthFactorService.getInteractionValue(s, 'nonexistent'));
    }

    @IsTest
    static void testClearCache() {
        // Populate cache
        StrengthFactorService.getActiveFactors();

        // Clear and re-fetch (should not throw)
        StrengthFactorService.clearCache();
        List<StrengthFactorService.StrengthFactor> factors =
            StrengthFactorService.getActiveFactors();
        System.assert(factors.size() >= 6, 'Should still return factors after cache clear');
    }

    @IsTest
    static void testAllFactorsHaveRequiredFields() {
        StrengthFactorService.clearCache();
        List<StrengthFactorService.StrengthFactor> factors =
            StrengthFactorService.getActiveFactors();

        for (StrengthFactorService.StrengthFactor f : factors) {
            System.assert(String.isNotBlank(f.developerName), 'developerName should not be blank');
            System.assert(String.isNotBlank(f.label), 'label should not be blank');
            System.assert(f.weight != null, 'weight should not be null');
            System.assert(String.isNotBlank(f.sourceType), 'sourceType should not be blank');
            System.assert(String.isNotBlank(f.sourceValue), 'sourceValue should not be blank');
        }
    }
}
