/**
 * Queueable job for asynchronous contact classification.
 * Uses Queueable instead of @future for better error handling and chaining support.
 */
public with sharing class ClassificationQueueable implements Queueable, Database.AllowsCallouts {

    private Id accountId;
    private List<Id> contactIds;

    public ClassificationQueueable(Id accountId, List<Id> contactIds) {
        this.accountId = accountId;
        this.contactIds = contactIds;
    }

    public void execute(QueueableContext context) {
        try {
            // Fetch interaction data
            InteractionDataService dataService = new InteractionDataService();
            InteractionDataService.InteractionBundle bundle =
                dataService.fetchInteractionData(accountId, contactIds);

            // Get the active provider
            IClassificationProvider provider = ClassificationProviderFactory.getProvider();

            // Classify
            Map<Id, ClassificationResult> results =
                provider.classifyContacts(accountId, contactIds, bundle);

            // Persist results
            persistClassifications(accountId, results);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Classification job failed for account ' + accountId + ': ' + e.getMessage());
        }
    }

    private void persistClassifications(Id accountId, Map<Id, ClassificationResult> results) {
        // Query existing classifications for upsert
        Map<String, Contact_Classification__c> existing = new Map<String, Contact_Classification__c>();
        for (Contact_Classification__c cc : [
            SELECT Id, Contact__c, Account__c
            FROM Contact_Classification__c
            WHERE Account__c = :accountId
            AND Contact__c IN :results.keySet()
            AND Is_User_Override__c = false
            WITH SECURITY_ENFORCED
        ]) {
            existing.put(String.valueOf(cc.Contact__c) + '_' + String.valueOf(cc.Account__c), cc);
        }

        List<Contact_Classification__c> toInsert = new List<Contact_Classification__c>();
        List<Contact_Classification__c> toUpdate = new List<Contact_Classification__c>();

        for (Id contactId : results.keySet()) {
            ClassificationResult result = results.get(contactId);
            String key = String.valueOf(contactId) + '_' + String.valueOf(accountId);

            Contact_Classification__c cc;
            if (existing.containsKey(key)) {
                cc = existing.get(key);
            } else {
                cc = new Contact_Classification__c(
                    Contact__c = contactId,
                    Account__c = accountId
                );
            }

            cc.Classification__c = result.classification;
            cc.Confidence_Score__c = result.confidenceScore;
            cc.Provider__c = result.providerName;
            cc.Is_User_Override__c = false;
            cc.Last_Classified__c = Datetime.now();

            if (cc.Id != null) {
                toUpdate.add(cc);
            } else {
                toInsert.add(cc);
            }
        }

        if (!toInsert.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.CREATABLE, toInsert
            );
            insert decision.getRecords();
        }
        if (!toUpdate.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE, toUpdate
            );
            update decision.getRecords();
        }
    }
}
