/**
 * Unit tests for ClassificationResult.
 * Covers validation, constructors, and valid classification constants.
 */
@IsTest
private class ClassificationResultTest {

    @IsTest
    static void testDefaultConstructor() {
        ClassificationResult result = new ClassificationResult();

        System.assertEquals('Unknown', result.classification);
        System.assertEquals(0.0, result.confidenceScore);
        System.assertEquals(false, result.isUserOverride);
        System.assertEquals(null, result.providerName);
    }

    @IsTest
    static void testParameterizedConstructor() {
        ClassificationResult result = new ClassificationResult(
            'Champion', 0.95, 'HeuristicClassificationProvider'
        );

        System.assertEquals('Champion', result.classification);
        System.assertEquals(0.95, result.confidenceScore);
        System.assertEquals('HeuristicClassificationProvider', result.providerName);
        System.assertEquals(false, result.isUserOverride);
    }

    @IsTest
    static void testIsValidWithValidClassification() {
        ClassificationResult result = new ClassificationResult('Champion', 0.85, 'TestProvider');
        System.assertEquals(true, result.isValid(), 'Valid classification should pass');
    }

    @IsTest
    static void testIsValidWithZeroConfidence() {
        ClassificationResult result = new ClassificationResult('Unknown', 0.0, 'TestProvider');
        System.assertEquals(true, result.isValid(), 'Zero confidence should be valid');
    }

    @IsTest
    static void testIsValidWithMaxConfidence() {
        ClassificationResult result = new ClassificationResult('Blocker', 1.0, 'TestProvider');
        System.assertEquals(true, result.isValid(), 'Max confidence should be valid');
    }

    @IsTest
    static void testIsInvalidClassification() {
        ClassificationResult result = new ClassificationResult('NotAType', 0.5, 'TestProvider');
        System.assertEquals(false, result.isValid(), 'Invalid classification name should fail');
    }

    @IsTest
    static void testIsInvalidNegativeConfidence() {
        ClassificationResult result = new ClassificationResult('Champion', -0.1, 'TestProvider');
        System.assertEquals(false, result.isValid(), 'Negative confidence should fail');
    }

    @IsTest
    static void testIsInvalidConfidenceAboveOne() {
        ClassificationResult result = new ClassificationResult('Champion', 1.5, 'TestProvider');
        System.assertEquals(false, result.isValid(), 'Confidence above 1.0 should fail');
    }

    @IsTest
    static void testValidClassificationsContainsAllExpected() {
        Set<String> expected = new Set<String>{
            'Champion', 'Economic Buyer', 'Technical Buyer', 'Blocker',
            'Influencer', 'End User', 'Detractor', 'Unknown'
        };

        System.assertEquals(8, ClassificationResult.VALID_CLASSIFICATIONS.size(),
            'Should have exactly 8 valid classifications');

        for (String cls : expected) {
            System.assert(ClassificationResult.VALID_CLASSIFICATIONS.contains(cls),
                'Missing expected classification: ' + cls);
        }
    }

    @IsTest
    static void testAllValidClassificationsPassValidation() {
        for (String cls : ClassificationResult.VALID_CLASSIFICATIONS) {
            ClassificationResult result = new ClassificationResult(cls, 0.5, 'TestProvider');
            System.assertEquals(true, result.isValid(),
                'Classification "' + cls + '" should be valid');
        }
    }
}
