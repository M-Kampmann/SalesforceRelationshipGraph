/**
 * Unit tests for ClassificationProviderFactory.
 */
@IsTest
private class ClassificationProviderFactoryTest {

    @IsTest
    static void testGetProviderReturnsHeuristicAsFallback() {
        // Agentforce won't be available in test context, should fall back to heuristic
        Test.startTest();
        IClassificationProvider provider = ClassificationProviderFactory.getProvider();
        Test.stopTest();

        System.assertNotEquals(null, provider, 'Should return a provider');
        // In test context, Agentforce callout won't work, so expect heuristic fallback
        System.assertEquals('HeuristicClassificationProvider', provider.getProviderName());
    }

    @IsTest
    static void testGetProviderByName() {
        Test.startTest();
        IClassificationProvider provider =
            ClassificationProviderFactory.getProvider('HeuristicClassificationProvider');
        Test.stopTest();

        System.assertEquals('HeuristicClassificationProvider', provider.getProviderName());
    }

    @IsTest
    static void testGetUnknownProviderFallsBack() {
        Test.startTest();
        IClassificationProvider provider =
            ClassificationProviderFactory.getProvider('NonExistentProvider');
        Test.stopTest();

        // Should fall back to heuristic
        System.assertEquals('HeuristicClassificationProvider', provider.getProviderName());
    }

    @IsTest
    static void testRegisterCustomProvider() {
        Test.startTest();
        ClassificationProviderFactory.registerProvider(
            'HeuristicClassificationProvider',
            HeuristicClassificationProvider.class
        );
        IClassificationProvider provider =
            ClassificationProviderFactory.getProvider('HeuristicClassificationProvider');
        Test.stopTest();

        System.assertNotEquals(null, provider);
    }
}
