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
        insert contacts;
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
        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < count; i++) {
            tasks.add(new Task(
                Subject = 'Test Task ' + i,
                WhoId = contactId,
                AccountId = accountId, // Note: Task doesn't have AccountId in all orgs
                Status = 'Completed'
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
        List<Relationship_Strength__c> strengths = new List<Relationship_Strength__c>();
        for (Integer i = 0; i < contacts.size(); i++) {
            strengths.add(new Relationship_Strength__c(
                Source_Contact__c = contacts[i].Id,
                Target_Record_Id__c = String.valueOf(accountId),
                Target_Object_Type__c = 'Account',
                Account__c = accountId,
                Strength__c = Math.mod(i * 17, 100) / 100.0, // Pseudo-random 0-1
                Interaction_Count__c = Math.mod(i * 7, 50),
                Co_Occurrence_Count__c = Math.mod(i * 3, 20),
                Last_Calculated__c = Datetime.now()
            ));
        }
        insert strengths;
        return strengths;
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
