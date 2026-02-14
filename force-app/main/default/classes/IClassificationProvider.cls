/**
 * Interface for contact role classification providers.
 * Implementations can use different AI/ML backends (Agentforce, heuristic rules, etc.).
 * Swap the active provider via Relationship_Graph_Config__mdt.Classification_Provider__c.
 */
public interface IClassificationProvider {

    /**
     * Classify a list of contacts within the context of an account.
     * @param accountId The account context for classification
     * @param contactIds The contacts to classify
     * @param interactionData Pre-fetched interaction data for the contacts
     * @return Map of Contact ID to ClassificationResult
     */
    Map<Id, ClassificationResult> classifyContacts(
        Id accountId,
        List<Id> contactIds,
        InteractionDataService.InteractionBundle interactionData
    );

    /**
     * Returns the name of this provider for auditing/logging.
     */
    String getProviderName();

    /**
     * Returns true if this provider is currently available (e.g., API is reachable).
     */
    Boolean isAvailable();
}
