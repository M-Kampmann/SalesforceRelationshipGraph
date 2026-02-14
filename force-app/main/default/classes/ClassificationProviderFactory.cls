/**
 * Factory for creating classification provider instances.
 * Reads the active provider from Relationship_Graph_Config__mdt.
 * Falls back to HeuristicClassificationProvider if the configured provider is unavailable.
 */
public with sharing class ClassificationProviderFactory {

    private static final Map<String, Type> PROVIDER_REGISTRY = new Map<String, Type>{
        'AgentforceClassificationProvider' => AgentforceClassificationProvider.class,
        'HeuristicClassificationProvider' => HeuristicClassificationProvider.class
    };

    /**
     * Get the active classification provider based on configuration.
     * Falls back to heuristic if the configured provider is unavailable.
     */
    public static IClassificationProvider getProvider() {
        String configuredProvider = getConfiguredProviderName();
        IClassificationProvider provider = createProvider(configuredProvider);

        if (provider != null && provider.isAvailable()) {
            return provider;
        }

        // Fall back to heuristic
        System.debug(LoggingLevel.WARN,
            'Configured provider "' + configuredProvider + '" unavailable, falling back to Heuristic');
        return new HeuristicClassificationProvider();
    }

    /**
     * Get a specific provider by name, regardless of configuration.
     */
    public static IClassificationProvider getProvider(String providerName) {
        IClassificationProvider provider = createProvider(providerName);
        return provider != null ? provider : new HeuristicClassificationProvider();
    }

    /**
     * Register a custom provider (for extensibility / testing).
     */
    public static void registerProvider(String name, Type providerType) {
        PROVIDER_REGISTRY.put(name, providerType);
    }

    @TestVisible
    private static String getConfiguredProviderName() {
        List<Relationship_Graph_Config__mdt> configs = [
            SELECT Classification_Provider__c
            FROM Relationship_Graph_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        if (!configs.isEmpty() && String.isNotBlank(configs[0].Classification_Provider__c)) {
            return configs[0].Classification_Provider__c;
        }

        return 'AgentforceClassificationProvider';
    }

    private static IClassificationProvider createProvider(String providerName) {
        if (String.isBlank(providerName) || !PROVIDER_REGISTRY.containsKey(providerName)) {
            System.debug(LoggingLevel.WARN, 'Unknown provider: ' + providerName);
            return null;
        }

        try {
            Type providerType = PROVIDER_REGISTRY.get(providerName);
            return (IClassificationProvider) providerType.newInstance();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Failed to create provider: ' + e.getMessage());
            return null;
        }
    }
}
