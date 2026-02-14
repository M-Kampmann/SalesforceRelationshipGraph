/**
 * Bulk data fetching service for interaction data.
 * Fetches all relevant interaction data for an account's contacts in minimal SOQL queries.
 * Computes co-occurrence analysis (who appears together on emails/meetings).
 *
 * Design: One query per object type (not per contact) to stay within governor limits.
 * For 200 contacts across 6 object types = 6 SOQL queries, not 1,200.
 */
public with sharing class InteractionDataService {

    // Negative sentiment keywords in email subjects
    @TestVisible
    private static final Set<String> NEGATIVE_KEYWORDS = new Set<String>{
        'concern', 'issue', 'problem', 'delay', 'cancel', 'disappointed',
        'frustrated', 'unhappy', 'escalat', 'complain', 'risk', 'blocker'
    };

    // Positive sentiment keywords in email subjects
    @TestVisible
    private static final Set<String> POSITIVE_KEYWORDS = new Set<String>{
        'thank', 'great', 'excited', 'looking forward', 'appreciate',
        'excellent', 'perfect', 'love', 'recommend', 'champion', 'advocate'
    };

    /**
     * Fetch all interaction data for contacts related to an account.
     * Returns a bundle containing per-contact summaries and co-occurrence data.
     */
    public InteractionBundle fetchInteractionData(Id accountId, List<Id> contactIds) {
        InteractionBundle bundle = new InteractionBundle();
        Set<Id> contactIdSet = new Set<Id>(contactIds);

        // Initialize summaries for all contacts
        for (Id cId : contactIds) {
            bundle.contactSummaries.put(cId, new ContactInteractionSummary());
        }

        // Fetch data in bulk — one query per object type
        fetchEmailData(accountId, contactIdSet, bundle);
        fetchEventData(accountId, contactIdSet, bundle);
        fetchTaskData(accountId, contactIdSet, bundle);
        fetchOpportunityRoles(accountId, contactIdSet, bundle);
        computeCoOccurrences(bundle);

        return bundle;
    }

    /**
     * Fetch contacts related to an account (via AccountContactRelation or Account lookup).
     */
    public List<Id> getAccountContactIds(Id accountId) {
        Set<Id> contactIds = new Set<Id>();

        // Direct account contacts
        for (Contact c : [
            SELECT Id FROM Contact
            WHERE AccountId = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 1000
        ]) {
            contactIds.add(c.Id);
        }

        // AccountContactRelation (indirect relationships)
        for (AccountContactRelation acr : [
            SELECT ContactId FROM AccountContactRelation
            WHERE AccountId = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 1000
        ]) {
            contactIds.add(acr.ContactId);
        }

        return new List<Id>(contactIds);
    }

    private void fetchEmailData(Id accountId, Set<Id> contactIds, InteractionBundle bundle) {
        // EmailMessage uses EmailMessageRelation to link to contacts
        Map<Id, List<Id>> emailToContacts = new Map<Id, List<Id>>();

        for (EmailMessageRelation emr : [
            SELECT EmailMessageId, RelationId, RelationType, EmailMessage.MessageDate
            FROM EmailMessageRelation
            WHERE RelationId IN :contactIds
            AND EmailMessage.RelatedToId = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ]) {
            Id contactId = emr.RelationId;
            ContactInteractionSummary summary = bundle.contactSummaries.get(contactId);
            if (summary == null) continue;

            if (emr.RelationType == 'FromAddress') {
                summary.emailsSent++;
            } else {
                summary.emailsReceived++;
            }
            summary.updateLastInteractionDate(emr.EmailMessage?.MessageDate?.date());

            // Track email-to-contacts for co-occurrence
            if (!emailToContacts.containsKey(emr.EmailMessageId)) {
                emailToContacts.put(emr.EmailMessageId, new List<Id>());
            }
            emailToContacts.get(emr.EmailMessageId).add(contactId);
        }

        // Store email co-occurrences
        bundle.emailCoOccurrences = emailToContacts;

        // Fetch email subjects for sentiment analysis
        Set<Id> emailIds = emailToContacts.keySet();
        if (!emailIds.isEmpty()) {
            Map<Id, EmailMessage> emails = new Map<Id, EmailMessage>([
                SELECT Id, Subject FROM EmailMessage
                WHERE Id IN :emailIds
                WITH SECURITY_ENFORCED
            ]);

            // Build reverse map: contact → email subjects
            for (Id emailId : emailToContacts.keySet()) {
                EmailMessage em = emails.get(emailId);
                if (em == null || String.isBlank(em.Subject)) continue;

                String subjectLower = em.Subject.toLowerCase();
                for (Id contactId : emailToContacts.get(emailId)) {
                    ContactInteractionSummary summary = bundle.contactSummaries.get(contactId);
                    if (summary == null) continue;

                    for (String keyword : NEGATIVE_KEYWORDS) {
                        if (subjectLower.contains(keyword)) {
                            summary.negativeSignalCount++;
                            break;
                        }
                    }
                    for (String keyword : POSITIVE_KEYWORDS) {
                        if (subjectLower.contains(keyword)) {
                            summary.positiveSignalCount++;
                            break;
                        }
                    }
                }
            }
        }
    }

    private void fetchEventData(Id accountId, Set<Id> contactIds, InteractionBundle bundle) {
        // Events (meetings) linked via EventRelation
        Map<Id, List<Id>> eventToContacts = new Map<Id, List<Id>>();

        for (EventRelation er : [
            SELECT EventId, RelationId, Status, Event.ActivityDate
            FROM EventRelation
            WHERE RelationId IN :contactIds
            AND Event.AccountId = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ]) {
            Id contactId = er.RelationId;
            ContactInteractionSummary summary = bundle.contactSummaries.get(contactId);
            if (summary == null) continue;

            if (er.Status == 'Accepted' || er.Status == null) {
                summary.meetingsAttended++;
            } else if (er.Status == 'Declined') {
                summary.meetingsDeclined++;
            }
            summary.updateLastInteractionDate(er.Event?.ActivityDate);

            // Track event-to-contacts for co-occurrence
            if (!eventToContacts.containsKey(er.EventId)) {
                eventToContacts.put(er.EventId, new List<Id>());
            }
            eventToContacts.get(er.EventId).add(contactId);
        }

        bundle.eventCoOccurrences = eventToContacts;
    }

    private void fetchTaskData(Id accountId, Set<Id> contactIds, InteractionBundle bundle) {
        for (Task t : [
            SELECT WhoId, Status, ActivityDate
            FROM Task
            WHERE WhoId IN :contactIds
            AND AccountId = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 10000
        ]) {
            ContactInteractionSummary summary = bundle.contactSummaries.get(t.WhoId);
            if (summary == null) continue;

            if (t.Status == 'Completed') {
                summary.tasksCompleted++;
            }
            summary.updateLastInteractionDate(t.ActivityDate);
        }
    }

    private void fetchOpportunityRoles(Id accountId, Set<Id> contactIds, InteractionBundle bundle) {
        for (OpportunityContactRole ocr : [
            SELECT ContactId, Role, Opportunity.Name
            FROM OpportunityContactRole
            WHERE ContactId IN :contactIds
            AND Opportunity.AccountId = :accountId
            WITH SECURITY_ENFORCED
            LIMIT 5000
        ]) {
            ContactInteractionSummary summary = bundle.contactSummaries.get(ocr.ContactId);
            if (summary == null) continue;

            summary.hasOpportunityRole = true;
            summary.opportunityRole = ocr.Role;
        }
    }

    /**
     * Compute co-occurrence counts: how many times two contacts appear on the same email or meeting.
     */
    private void computeCoOccurrences(InteractionBundle bundle) {
        // Process email co-occurrences
        processCoOccurrences(bundle.emailCoOccurrences, bundle);

        // Process event co-occurrences
        processCoOccurrences(bundle.eventCoOccurrences, bundle);
    }

    private void processCoOccurrences(Map<Id, List<Id>> itemToContacts, InteractionBundle bundle) {
        if (itemToContacts == null) return;

        for (List<Id> contacts : itemToContacts.values()) {
            if (contacts.size() < 2) continue;

            // For each pair of contacts on the same item, increment co-occurrence
            for (Integer i = 0; i < contacts.size(); i++) {
                ContactInteractionSummary summaryI = bundle.contactSummaries.get(contacts[i]);
                if (summaryI == null) continue;

                for (Integer j = i + 1; j < contacts.size(); j++) {
                    summaryI.coOccurrenceCount++;

                    ContactInteractionSummary summaryJ = bundle.contactSummaries.get(contacts[j]);
                    if (summaryJ != null) {
                        summaryJ.coOccurrenceCount++;
                    }

                    // Track the pair for edge generation
                    String pairKey = generatePairKey(contacts[i], contacts[j]);
                    if (!bundle.coOccurrencePairs.containsKey(pairKey)) {
                        bundle.coOccurrencePairs.put(pairKey, 0);
                    }
                    bundle.coOccurrencePairs.put(pairKey, bundle.coOccurrencePairs.get(pairKey) + 1);
                }
            }
        }
    }

    private String generatePairKey(Id id1, Id id2) {
        // Ensure consistent ordering for the pair key
        if (String.valueOf(id1) < String.valueOf(id2)) {
            return String.valueOf(id1) + '_' + String.valueOf(id2);
        }
        return String.valueOf(id2) + '_' + String.valueOf(id1);
    }

    // ─── Inner Classes ────────────────────────────────────────────────

    /**
     * Bundle containing all interaction data for a set of contacts.
     */
    public class InteractionBundle {
        public Map<Id, ContactInteractionSummary> contactSummaries { get; set; }
        public Map<Id, List<Id>> emailCoOccurrences { get; set; }
        public Map<Id, List<Id>> eventCoOccurrences { get; set; }
        public Map<String, Integer> coOccurrencePairs { get; set; }

        public InteractionBundle() {
            this.contactSummaries = new Map<Id, ContactInteractionSummary>();
            this.emailCoOccurrences = new Map<Id, List<Id>>();
            this.eventCoOccurrences = new Map<Id, List<Id>>();
            this.coOccurrencePairs = new Map<String, Integer>();
        }

        public ContactInteractionSummary getContactSummary(Id contactId) {
            return contactSummaries.get(contactId);
        }
    }

    /**
     * Summary of a single contact's interaction data.
     */
    public class ContactInteractionSummary {
        public Integer emailsSent { get; set; }
        public Integer emailsReceived { get; set; }
        public Integer meetingsAttended { get; set; }
        public Integer meetingsDeclined { get; set; }
        public Integer tasksCompleted { get; set; }
        public Integer coOccurrenceCount { get; set; }
        public Boolean hasOpportunityRole { get; set; }
        public String opportunityRole { get; set; }
        public Integer negativeSignalCount { get; set; }
        public Integer positiveSignalCount { get; set; }
        public Date lastInteractionDate { get; set; }

        public ContactInteractionSummary() {
            this.emailsSent = 0;
            this.emailsReceived = 0;
            this.meetingsAttended = 0;
            this.meetingsDeclined = 0;
            this.tasksCompleted = 0;
            this.coOccurrenceCount = 0;
            this.hasOpportunityRole = false;
            this.negativeSignalCount = 0;
            this.positiveSignalCount = 0;
        }

        /**
         * Track the most recent interaction date for time-decay scoring.
         */
        public void updateLastInteractionDate(Date d) {
            if (d != null && (this.lastInteractionDate == null || d > this.lastInteractionDate)) {
                this.lastInteractionDate = d;
            }
        }

        /**
         * Total interaction count across all channels.
         */
        public Integer getTotalInteractions() {
            return emailsSent + emailsReceived + meetingsAttended + tasksCompleted;
        }
    }
}
