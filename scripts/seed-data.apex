// Seed data for Relationship Graph demo
// Creates 3 accounts with contacts, opportunities, tasks, events, and classifications

// ─── Accounts ────────────────────────────────────────────────────────
List<Account> accounts = new List<Account>{
    new Account(Name = 'Acme Corporation', Industry = 'Technology', BillingCity = 'San Francisco', AnnualRevenue = 50000000, NumberOfEmployees = 500),
    new Account(Name = 'Global Industries', Industry = 'Manufacturing', BillingCity = 'Chicago', AnnualRevenue = 120000000, NumberOfEmployees = 2000),
    new Account(Name = 'Pinnacle Solutions', Industry = 'Consulting', BillingCity = 'New York', AnnualRevenue = 25000000, NumberOfEmployees = 200)
};
insert accounts;
System.debug('Inserted ' + accounts.size() + ' accounts');

// ─── Contacts ────────────────────────────────────────────────────────
List<Contact> contacts = new List<Contact>();

// Acme Corp contacts (8)
contacts.add(new Contact(FirstName = 'Sarah', LastName = 'Chen', AccountId = accounts[0].Id, Title = 'VP of Engineering', Email = 'sarah.chen@acme.com', Phone = '415-555-0101'));
contacts.add(new Contact(FirstName = 'Michael', LastName = 'Torres', AccountId = accounts[0].Id, Title = 'CTO', Email = 'michael.torres@acme.com', Phone = '415-555-0102'));
contacts.add(new Contact(FirstName = 'Emily', LastName = 'Williams', AccountId = accounts[0].Id, Title = 'Director of Procurement', Email = 'emily.williams@acme.com', Phone = '415-555-0103'));
contacts.add(new Contact(FirstName = 'James', LastName = 'Park', AccountId = accounts[0].Id, Title = 'Senior Developer', Email = 'james.park@acme.com', Phone = '415-555-0104'));
contacts.add(new Contact(FirstName = 'Lisa', LastName = 'Kumar', AccountId = accounts[0].Id, Title = 'Product Manager', Email = 'lisa.kumar@acme.com', Phone = '415-555-0105'));
contacts.add(new Contact(FirstName = 'David', LastName = 'Anderson', AccountId = accounts[0].Id, Title = 'CFO', Email = 'david.anderson@acme.com', Phone = '415-555-0106'));
contacts.add(new Contact(FirstName = 'Rachel', LastName = 'Martinez', AccountId = accounts[0].Id, Title = 'IT Manager', Email = 'rachel.martinez@acme.com', Phone = '415-555-0107'));
contacts.add(new Contact(FirstName = 'Tom', LastName = 'Brown', AccountId = accounts[0].Id, Title = 'Intern', Email = 'tom.brown@acme.com', Phone = '415-555-0108'));

// Global Industries contacts (6)
contacts.add(new Contact(FirstName = 'Jennifer', LastName = 'Lopez', AccountId = accounts[1].Id, Title = 'CEO', Email = 'jennifer.lopez@global.com', Phone = '312-555-0201'));
contacts.add(new Contact(FirstName = 'Robert', LastName = 'Kim', AccountId = accounts[1].Id, Title = 'VP Sales', Email = 'robert.kim@global.com', Phone = '312-555-0202'));
contacts.add(new Contact(FirstName = 'Amanda', LastName = 'Johnson', AccountId = accounts[1].Id, Title = 'Technical Lead', Email = 'amanda.johnson@global.com', Phone = '312-555-0203'));
contacts.add(new Contact(FirstName = 'Kevin', LastName = 'Wright', AccountId = accounts[1].Id, Title = 'Operations Director', Email = 'kevin.wright@global.com', Phone = '312-555-0204'));
contacts.add(new Contact(FirstName = 'Sophia', LastName = 'Lee', AccountId = accounts[1].Id, Title = 'Security Analyst', Email = 'sophia.lee@global.com', Phone = '312-555-0205'));
contacts.add(new Contact(FirstName = 'Brian', LastName = 'Davis', AccountId = accounts[1].Id, Title = 'Junior Dev', Email = 'brian.davis@global.com', Phone = '312-555-0206'));

// Pinnacle Solutions contacts (5)
contacts.add(new Contact(FirstName = 'Alexandra', LastName = 'Petrova', AccountId = accounts[2].Id, Title = 'Managing Partner', Email = 'alex.petrova@pinnacle.com', Phone = '212-555-0301'));
contacts.add(new Contact(FirstName = 'Marcus', LastName = 'Thompson', AccountId = accounts[2].Id, Title = 'Head of Technology', Email = 'marcus.thompson@pinnacle.com', Phone = '212-555-0302'));
contacts.add(new Contact(FirstName = 'Diana', LastName = 'Reyes', AccountId = accounts[2].Id, Title = 'Business Analyst', Email = 'diana.reyes@pinnacle.com', Phone = '212-555-0303'));
contacts.add(new Contact(FirstName = 'Chris', LastName = 'O\'Brien', AccountId = accounts[2].Id, Title = 'Finance Director', Email = 'chris.obrien@pinnacle.com', Phone = '212-555-0304'));
contacts.add(new Contact(FirstName = 'Nina', LastName = 'Patel', AccountId = accounts[2].Id, Title = 'Consultant', Email = 'nina.patel@pinnacle.com', Phone = '212-555-0305'));

insert contacts;
System.debug('Inserted ' + contacts.size() + ' contacts');

// ─── Opportunities ───────────────────────────────────────────────────
List<Opportunity> opps = new List<Opportunity>{
    new Opportunity(Name = 'Acme - Platform License', AccountId = accounts[0].Id, StageName = 'Negotiation/Review', Amount = 250000, CloseDate = Date.today().addDays(30)),
    new Opportunity(Name = 'Acme - Professional Services', AccountId = accounts[0].Id, StageName = 'Proposal/Price Quote', Amount = 75000, CloseDate = Date.today().addDays(60)),
    new Opportunity(Name = 'Global - Enterprise Deal', AccountId = accounts[1].Id, StageName = 'Qualification', Amount = 500000, CloseDate = Date.today().addDays(90)),
    new Opportunity(Name = 'Pinnacle - Consulting Engagement', AccountId = accounts[2].Id, StageName = 'Perception Analysis', Amount = 150000, CloseDate = Date.today().addDays(45))
};
insert opps;
System.debug('Inserted ' + opps.size() + ' opportunities');

// ─── Opportunity Contact Roles ───────────────────────────────────────
List<OpportunityContactRole> roles = new List<OpportunityContactRole>{
    // Acme Platform License
    new OpportunityContactRole(OpportunityId = opps[0].Id, ContactId = contacts[0].Id, Role = 'Decision Maker', IsPrimary = true),
    new OpportunityContactRole(OpportunityId = opps[0].Id, ContactId = contacts[1].Id, Role = 'Technical Approver'),
    new OpportunityContactRole(OpportunityId = opps[0].Id, ContactId = contacts[2].Id, Role = 'Economic Buyer'),
    new OpportunityContactRole(OpportunityId = opps[0].Id, ContactId = contacts[5].Id, Role = 'Economic Buyer'),
    // Acme Services
    new OpportunityContactRole(OpportunityId = opps[1].Id, ContactId = contacts[3].Id, Role = 'Technical Approver'),
    new OpportunityContactRole(OpportunityId = opps[1].Id, ContactId = contacts[4].Id, Role = 'Business User'),
    // Global Enterprise
    new OpportunityContactRole(OpportunityId = opps[2].Id, ContactId = contacts[8].Id, Role = 'Executive Sponsor', IsPrimary = true),
    new OpportunityContactRole(OpportunityId = opps[2].Id, ContactId = contacts[9].Id, Role = 'Decision Maker'),
    new OpportunityContactRole(OpportunityId = opps[2].Id, ContactId = contacts[10].Id, Role = 'Technical Approver'),
    // Pinnacle Consulting
    new OpportunityContactRole(OpportunityId = opps[3].Id, ContactId = contacts[14].Id, Role = 'Decision Maker', IsPrimary = true),
    new OpportunityContactRole(OpportunityId = opps[3].Id, ContactId = contacts[15].Id, Role = 'Technical Approver')
};
insert roles;
System.debug('Inserted ' + roles.size() + ' opportunity contact roles');

// ─── Tasks (activity history) ────────────────────────────────────────
List<Task> tasks = new List<Task>();

// Sarah Chen - Champion (high activity)
for (Integer i = 0; i < 15; i++) {
    tasks.add(new Task(Subject = 'Call with Sarah Chen #' + i, WhoId = contacts[0].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 5)));
}
// Michael Torres - Technical Buyer
for (Integer i = 0; i < 8; i++) {
    tasks.add(new Task(Subject = 'Technical Review with Michael #' + i, WhoId = contacts[1].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 7)));
}
// Emily Williams - Economic Buyer
for (Integer i = 0; i < 6; i++) {
    tasks.add(new Task(Subject = 'Procurement Meeting with Emily #' + i, WhoId = contacts[2].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 10)));
}
// James Park - Influencer
for (Integer i = 0; i < 4; i++) {
    tasks.add(new Task(Subject = 'Demo with James #' + i, WhoId = contacts[3].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 14)));
}
// Lisa Kumar - End User
for (Integer i = 0; i < 3; i++) {
    tasks.add(new Task(Subject = 'Requirements call with Lisa #' + i, WhoId = contacts[4].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 20)));
}
// David Anderson - Blocker (few recent activities, blocks progress)
tasks.add(new Task(Subject = 'Budget review with David', WhoId = contacts[5].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-60)));
tasks.add(new Task(Subject = 'Escalation call with David', WhoId = contacts[5].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-45)));
// Tom Brown - passive (1 old task)
tasks.add(new Task(Subject = 'Intro call with Tom', WhoId = contacts[7].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-120)));

// Global Industries
for (Integer i = 0; i < 10; i++) {
    tasks.add(new Task(Subject = 'Exec briefing with Jennifer #' + i, WhoId = contacts[8].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 6)));
}
for (Integer i = 0; i < 7; i++) {
    tasks.add(new Task(Subject = 'Sales call with Robert #' + i, WhoId = contacts[9].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 8)));
}
for (Integer i = 0; i < 5; i++) {
    tasks.add(new Task(Subject = 'Tech eval with Amanda #' + i, WhoId = contacts[10].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 9)));
}

// Pinnacle
for (Integer i = 0; i < 12; i++) {
    tasks.add(new Task(Subject = 'Strategy session with Alexandra #' + i, WhoId = contacts[14].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 4)));
}
for (Integer i = 0; i < 6; i++) {
    tasks.add(new Task(Subject = 'Architecture review with Marcus #' + i, WhoId = contacts[15].Id, Status = 'Completed', ActivityDate = Date.today().addDays(-i * 7)));
}

insert tasks;
System.debug('Inserted ' + tasks.size() + ' tasks');

// ─── Events ──────────────────────────────────────────────────────────
List<Event> events = new List<Event>();

// Co-occurrence events (multiple contacts on same event)
events.add(new Event(Subject = 'Q4 Planning Meeting', WhoId = contacts[0].Id, StartDateTime = DateTime.now().addDays(-10), DurationInMinutes = 60));
events.add(new Event(Subject = 'Q4 Planning Meeting', WhoId = contacts[1].Id, StartDateTime = DateTime.now().addDays(-10), DurationInMinutes = 60));
events.add(new Event(Subject = 'Q4 Planning Meeting', WhoId = contacts[4].Id, StartDateTime = DateTime.now().addDays(-10), DurationInMinutes = 60));

events.add(new Event(Subject = 'Contract Review', WhoId = contacts[0].Id, StartDateTime = DateTime.now().addDays(-20), DurationInMinutes = 90));
events.add(new Event(Subject = 'Contract Review', WhoId = contacts[2].Id, StartDateTime = DateTime.now().addDays(-20), DurationInMinutes = 90));
events.add(new Event(Subject = 'Contract Review', WhoId = contacts[5].Id, StartDateTime = DateTime.now().addDays(-20), DurationInMinutes = 90));

events.add(new Event(Subject = 'Technical Deep Dive', WhoId = contacts[1].Id, StartDateTime = DateTime.now().addDays(-15), DurationInMinutes = 120));
events.add(new Event(Subject = 'Technical Deep Dive', WhoId = contacts[3].Id, StartDateTime = DateTime.now().addDays(-15), DurationInMinutes = 120));

// Global Industries events
events.add(new Event(Subject = 'Executive Presentation', WhoId = contacts[8].Id, StartDateTime = DateTime.now().addDays(-5), DurationInMinutes = 60));
events.add(new Event(Subject = 'Executive Presentation', WhoId = contacts[9].Id, StartDateTime = DateTime.now().addDays(-5), DurationInMinutes = 60));
events.add(new Event(Subject = 'Executive Presentation', WhoId = contacts[11].Id, StartDateTime = DateTime.now().addDays(-5), DurationInMinutes = 60));

events.add(new Event(Subject = 'Security Assessment', WhoId = contacts[10].Id, StartDateTime = DateTime.now().addDays(-8), DurationInMinutes = 90));
events.add(new Event(Subject = 'Security Assessment', WhoId = contacts[12].Id, StartDateTime = DateTime.now().addDays(-8), DurationInMinutes = 90));

// Pinnacle events
events.add(new Event(Subject = 'Kickoff Meeting', WhoId = contacts[14].Id, StartDateTime = DateTime.now().addDays(-3), DurationInMinutes = 60));
events.add(new Event(Subject = 'Kickoff Meeting', WhoId = contacts[15].Id, StartDateTime = DateTime.now().addDays(-3), DurationInMinutes = 60));
events.add(new Event(Subject = 'Kickoff Meeting', WhoId = contacts[16].Id, StartDateTime = DateTime.now().addDays(-3), DurationInMinutes = 60));

insert events;
System.debug('Inserted ' + events.size() + ' events');

// ─── Contact Classifications ─────────────────────────────────────────
List<Contact_Classification__c> classifications = new List<Contact_Classification__c>();

// Acme Corp
classifications.add(new Contact_Classification__c(Contact__c = contacts[0].Id, Account__c = accounts[0].Id, Classification__c = 'Champion', Confidence_Score__c = 0.92, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[1].Id, Account__c = accounts[0].Id, Classification__c = 'Technical Buyer', Confidence_Score__c = 0.85, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[2].Id, Account__c = accounts[0].Id, Classification__c = 'Economic Buyer', Confidence_Score__c = 0.78, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[3].Id, Account__c = accounts[0].Id, Classification__c = 'Influencer', Confidence_Score__c = 0.70, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[4].Id, Account__c = accounts[0].Id, Classification__c = 'End User', Confidence_Score__c = 0.65, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[5].Id, Account__c = accounts[0].Id, Classification__c = 'Blocker', Confidence_Score__c = 0.72, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[6].Id, Account__c = accounts[0].Id, Classification__c = 'End User', Confidence_Score__c = 0.55, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[7].Id, Account__c = accounts[0].Id, Classification__c = 'Unknown', Confidence_Score__c = 0.30, Provider__c = 'Heuristic'));

// Global Industries
classifications.add(new Contact_Classification__c(Contact__c = contacts[8].Id, Account__c = accounts[1].Id, Classification__c = 'Champion', Confidence_Score__c = 0.90, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[9].Id, Account__c = accounts[1].Id, Classification__c = 'Economic Buyer', Confidence_Score__c = 0.82, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[10].Id, Account__c = accounts[1].Id, Classification__c = 'Technical Buyer', Confidence_Score__c = 0.80, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[11].Id, Account__c = accounts[1].Id, Classification__c = 'Influencer', Confidence_Score__c = 0.68, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[12].Id, Account__c = accounts[1].Id, Classification__c = 'Detractor', Confidence_Score__c = 0.60, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[13].Id, Account__c = accounts[1].Id, Classification__c = 'Unknown', Confidence_Score__c = 0.25, Provider__c = 'Heuristic'));

// Pinnacle Solutions
classifications.add(new Contact_Classification__c(Contact__c = contacts[14].Id, Account__c = accounts[2].Id, Classification__c = 'Champion', Confidence_Score__c = 0.95, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[15].Id, Account__c = accounts[2].Id, Classification__c = 'Technical Buyer', Confidence_Score__c = 0.88, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[16].Id, Account__c = accounts[2].Id, Classification__c = 'Influencer', Confidence_Score__c = 0.72, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[17].Id, Account__c = accounts[2].Id, Classification__c = 'Blocker', Confidence_Score__c = 0.65, Provider__c = 'Heuristic'));
classifications.add(new Contact_Classification__c(Contact__c = contacts[18].Id, Account__c = accounts[2].Id, Classification__c = 'End User', Confidence_Score__c = 0.50, Provider__c = 'Heuristic'));

insert classifications;
System.debug('Inserted ' + classifications.size() + ' classifications');

// ─── Relationship Strengths ──────────────────────────────────────────
List<Relationship_Strength__c> strengths = new List<Relationship_Strength__c>();

// Acme Corp - contact-to-account strengths
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[0].Id, Account__c = accounts[0].Id, Target_Record_Id__c = accounts[0].Id, Target_Object_Type__c = 'Account', Strength__c = 0.95, Interaction_Count__c = 15, Last_Interaction_Date__c = Date.today()));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[1].Id, Account__c = accounts[0].Id, Target_Record_Id__c = accounts[0].Id, Target_Object_Type__c = 'Account', Strength__c = 0.80, Interaction_Count__c = 8, Last_Interaction_Date__c = Date.today().addDays(-7)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[2].Id, Account__c = accounts[0].Id, Target_Record_Id__c = accounts[0].Id, Target_Object_Type__c = 'Account', Strength__c = 0.65, Interaction_Count__c = 6, Last_Interaction_Date__c = Date.today().addDays(-10)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[3].Id, Account__c = accounts[0].Id, Target_Record_Id__c = accounts[0].Id, Target_Object_Type__c = 'Account', Strength__c = 0.50, Interaction_Count__c = 4, Last_Interaction_Date__c = Date.today().addDays(-14)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[4].Id, Account__c = accounts[0].Id, Target_Record_Id__c = accounts[0].Id, Target_Object_Type__c = 'Account', Strength__c = 0.40, Interaction_Count__c = 3, Last_Interaction_Date__c = Date.today().addDays(-20)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[5].Id, Account__c = accounts[0].Id, Target_Record_Id__c = accounts[0].Id, Target_Object_Type__c = 'Account', Strength__c = 0.25, Interaction_Count__c = 2, Last_Interaction_Date__c = Date.today().addDays(-45)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[6].Id, Account__c = accounts[0].Id, Target_Record_Id__c = accounts[0].Id, Target_Object_Type__c = 'Account', Strength__c = 0.20, Interaction_Count__c = 1, Last_Interaction_Date__c = Date.today().addDays(-60)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[7].Id, Account__c = accounts[0].Id, Target_Record_Id__c = accounts[0].Id, Target_Object_Type__c = 'Account', Strength__c = 0.05, Interaction_Count__c = 1, Last_Interaction_Date__c = Date.today().addDays(-120)));

// Acme - contact-to-opportunity strengths
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[0].Id, Account__c = accounts[0].Id, Target_Record_Id__c = opps[0].Id, Target_Object_Type__c = 'Opportunity', Strength__c = 0.85, Interaction_Count__c = 10));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[1].Id, Account__c = accounts[0].Id, Target_Record_Id__c = opps[0].Id, Target_Object_Type__c = 'Opportunity', Strength__c = 0.70, Interaction_Count__c = 5));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[2].Id, Account__c = accounts[0].Id, Target_Record_Id__c = opps[0].Id, Target_Object_Type__c = 'Opportunity', Strength__c = 0.60, Interaction_Count__c = 4));

// Acme - co-occurrence strengths (contact-to-contact)
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[0].Id, Account__c = accounts[0].Id, Target_Record_Id__c = contacts[1].Id, Target_Object_Type__c = 'Contact', Strength__c = 0.70, Co_Occurrence_Count__c = 5, Interaction_Count__c = 5));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[0].Id, Account__c = accounts[0].Id, Target_Record_Id__c = contacts[2].Id, Target_Object_Type__c = 'Contact', Strength__c = 0.45, Co_Occurrence_Count__c = 3, Interaction_Count__c = 3));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[1].Id, Account__c = accounts[0].Id, Target_Record_Id__c = contacts[3].Id, Target_Object_Type__c = 'Contact', Strength__c = 0.55, Co_Occurrence_Count__c = 4, Interaction_Count__c = 4));

// Global Industries
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[8].Id, Account__c = accounts[1].Id, Target_Record_Id__c = accounts[1].Id, Target_Object_Type__c = 'Account', Strength__c = 0.90, Interaction_Count__c = 10, Last_Interaction_Date__c = Date.today().addDays(-3)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[9].Id, Account__c = accounts[1].Id, Target_Record_Id__c = accounts[1].Id, Target_Object_Type__c = 'Account', Strength__c = 0.75, Interaction_Count__c = 7, Last_Interaction_Date__c = Date.today().addDays(-8)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[10].Id, Account__c = accounts[1].Id, Target_Record_Id__c = accounts[1].Id, Target_Object_Type__c = 'Account', Strength__c = 0.60, Interaction_Count__c = 5, Last_Interaction_Date__c = Date.today().addDays(-9)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[11].Id, Account__c = accounts[1].Id, Target_Record_Id__c = accounts[1].Id, Target_Object_Type__c = 'Account', Strength__c = 0.45, Interaction_Count__c = 3, Last_Interaction_Date__c = Date.today().addDays(-15)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[12].Id, Account__c = accounts[1].Id, Target_Record_Id__c = accounts[1].Id, Target_Object_Type__c = 'Account', Strength__c = 0.30, Interaction_Count__c = 2, Last_Interaction_Date__c = Date.today().addDays(-30)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[13].Id, Account__c = accounts[1].Id, Target_Record_Id__c = accounts[1].Id, Target_Object_Type__c = 'Account', Strength__c = 0.10, Interaction_Count__c = 1, Last_Interaction_Date__c = Date.today().addDays(-80)));

// Pinnacle Solutions
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[14].Id, Account__c = accounts[2].Id, Target_Record_Id__c = accounts[2].Id, Target_Object_Type__c = 'Account', Strength__c = 0.92, Interaction_Count__c = 12, Last_Interaction_Date__c = Date.today()));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[15].Id, Account__c = accounts[2].Id, Target_Record_Id__c = accounts[2].Id, Target_Object_Type__c = 'Account', Strength__c = 0.78, Interaction_Count__c = 6, Last_Interaction_Date__c = Date.today().addDays(-7)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[16].Id, Account__c = accounts[2].Id, Target_Record_Id__c = accounts[2].Id, Target_Object_Type__c = 'Account', Strength__c = 0.55, Interaction_Count__c = 4, Last_Interaction_Date__c = Date.today().addDays(-12)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[17].Id, Account__c = accounts[2].Id, Target_Record_Id__c = accounts[2].Id, Target_Object_Type__c = 'Account', Strength__c = 0.35, Interaction_Count__c = 2, Last_Interaction_Date__c = Date.today().addDays(-25)));
strengths.add(new Relationship_Strength__c(Source_Contact__c = contacts[18].Id, Account__c = accounts[2].Id, Target_Record_Id__c = accounts[2].Id, Target_Object_Type__c = 'Account', Strength__c = 0.20, Interaction_Count__c = 1, Last_Interaction_Date__c = Date.today().addDays(-40)));

insert strengths;
System.debug('Inserted ' + strengths.size() + ' relationship strengths');

System.debug('=== SEED DATA COMPLETE ===');
System.debug('Accounts: ' + accounts.size());
System.debug('Contacts: ' + contacts.size());
System.debug('Opportunities: ' + opps.size());
System.debug('Tasks: ' + tasks.size());
System.debug('Events: ' + events.size());
System.debug('Classifications: ' + classifications.size());
System.debug('Relationship Strengths: ' + strengths.size());
