/**
 * Test data factory for Relationship Graph unit tests.
 */
@IsTest
public class RelationshipGraphTestDataFactory {

    public static Account createAccount(String name) {
        Account a = new Account(Name = name, Industry = 'Technology');
        insert a;
        return a;
    }

    public static List<Contact> createContacts(Id accountId, Integer count) {
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                AccountId = accountId,
                Email = 'contact' + i + '@test.com',
                Title = getRandomTitle(i)
            ));
        }
        Database.DMLOptions dml = new Database.DMLOptions();
        dml.DuplicateRuleHeader.allowSave = true;
        Database.insert(contacts, dml);
        return contacts;
    }

    public static Opportunity createOpportunity(Id accountId, String name) {
        Opportunity opp = new Opportunity(
            Name = name,
            AccountId = accountId,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = 50000
        );
        insert opp;
        return opp;
    }

    public static List<Task> createTasks(Id contactId, Id accountId, Integer count) {
        return createTasks(contactId, accountId, count, 'Completed');
    }

    public static List<Task> createTasks(Id contactId, Id accountId, Integer count, String status) {
        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < count; i++) {
            tasks.add(new Task(
                Subject = 'Test Task ' + i,
                WhoId = contactId,
                Status = status
            ));
        }
        insert tasks;
        return tasks;
    }

    public static List<Contact_Classification__c> createClassifications(
        Id accountId, List<Contact> contacts, String classification
    ) {
        List<Contact_Classification__c> classifications = new List<Contact_Classification__c>();
        for (Contact c : contacts) {
            classifications.add(new Contact_Classification__c(
                Contact__c = c.Id,
                Account__c = accountId,
                Classification__c = classification,
                Confidence_Score__c = 0.85,
                Provider__c = 'HeuristicClassificationProvider',
                Is_User_Override__c = false,
                Last_Classified__c = Datetime.now()
            ));
        }
        insert classifications;
        return classifications;
    }

    public static List<Relationship_Strength__c> createStrengths(
        Id accountId, List<Contact> contacts
    ) {
        return createStrengths(accountId, contacts, null);
    }

    public static List<Relationship_Strength__c> createStrengths(
        Id accountId, List<Contact> contacts, Date lastInteractionDate
    ) {
        List<Relationship_Strength__c> strengths = new List<Relationship_Strength__c>();
        for (Integer i = 0; i < contacts.size(); i++) {
            strengths.add(new Relationship_Strength__c(
                Source_Contact__c = contacts[i].Id,
                Target_Record_Id__c = String.valueOf(accountId),
                Target_Object_Type__c = 'Account',
                Account__c = accountId,
                Strength__c = Math.mod(i * 17, 100) / 100.0,
                Interaction_Count__c = Math.mod(i * 7, 50),
                Co_Occurrence_Count__c = Math.mod(i * 3, 20),
                Last_Calculated__c = Datetime.now(),
                Last_Interaction_Date__c = lastInteractionDate != null
                    ? lastInteractionDate : Date.today()
            ));
        }
        insert strengths;
        return strengths;
    }

    public static List<Relationship_Strength__c> createCoOccurrenceStrengths(
        Id accountId, Id sourceContactId, Id targetContactId, Integer count
    ) {
        List<Relationship_Strength__c> records = new List<Relationship_Strength__c>();
        records.add(new Relationship_Strength__c(
            Source_Contact__c = sourceContactId,
            Target_Record_Id__c = String.valueOf(targetContactId),
            Target_Object_Type__c = 'Contact',
            Account__c = accountId,
            Strength__c = Math.min(count / 20.0, 1.0),
            Co_Occurrence_Count__c = count,
            Last_Calculated__c = Datetime.now()
        ));
        insert records;
        return records;
    }

    public static InteractionDataService.InteractionBundle createInteractionBundle(
        List<Contact> contacts
    ) {
        InteractionDataService.InteractionBundle bundle =
            new InteractionDataService.InteractionBundle();
        for (Contact c : contacts) {
            bundle.contactSummaries.put(c.Id,
                new InteractionDataService.ContactInteractionSummary());
        }
        return bundle;
    }

    private static String getRandomTitle(Integer index) {
        List<String> titles = new List<String>{
            'CEO', 'CTO', 'VP Engineering', 'Sales Manager',
            'Product Analyst', 'Director of IT', 'Account Executive',
            'Marketing Lead', 'CFO', 'Software Engineer'
        };
        return titles[Math.mod(index, titles.size())];
    }
}
