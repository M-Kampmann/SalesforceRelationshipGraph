/**
 * Rule-based contact classification provider.
 * Uses interaction patterns, titles, and engagement signals to classify contacts.
 * Serves as the fallback when AI providers (Agentforce) are unavailable.
 */
public with sharing class HeuristicClassificationProvider implements IClassificationProvider {

    private static final Map<String, Set<String>> TITLE_KEYWORDS = new Map<String, Set<String>>{
        'Economic Buyer' => new Set<String>{'ceo', 'cfo', 'coo', 'president', 'vp finance', 'vp of finance', 'chief', 'head of finance', 'director of finance', 'managing director'},
        'Technical Buyer' => new Set<String>{'cto', 'cio', 'vp engineering', 'vp of engineering', 'head of engineering', 'director of engineering', 'it director', 'technical director', 'head of it', 'vp technology'},
        'End User' => new Set<String>{'analyst', 'coordinator', 'specialist', 'associate', 'assistant', 'representative', 'agent'}
    };

    // Weights for different interaction types
    private static final Map<String, Decimal> INTERACTION_WEIGHTS = new Map<String, Decimal>{
        'email_sent' => 1.0,
        'email_received' => 1.5,
        'meeting_attended' => 3.0,
        'task_completed' => 1.0,
        'opportunity_contact_role' => 5.0
    };

    public Map<Id, ClassificationResult> classifyContacts(
        Id accountId,
        List<Id> contactIds,
        InteractionDataService.InteractionBundle interactionData
    ) {
        Map<Id, ClassificationResult> results = new Map<Id, ClassificationResult>();

        // Fetch contact details for title-based classification
        Map<Id, Contact> contacts = new Map<Id, Contact>([
            SELECT Id, Title, Email, Name
            FROM Contact
            WHERE Id IN :contactIds
            WITH SECURITY_ENFORCED
        ]);

        for (Id contactId : contactIds) {
            Contact c = contacts.get(contactId);
            InteractionDataService.ContactInteractionSummary summary =
                interactionData.getContactSummary(contactId);

            ClassificationResult result = classifySingleContact(c, summary, interactionData);
            results.put(contactId, result);
        }

        return results;
    }

    public String getProviderName() {
        return 'HeuristicClassificationProvider';
    }

    public Boolean isAvailable() {
        return true; // Always available as rule-based
    }

    private ClassificationResult classifySingleContact(
        Contact c,
        InteractionDataService.ContactInteractionSummary summary,
        InteractionDataService.InteractionBundle bundle
    ) {
        // Score each possible classification
        Map<String, Decimal> scores = new Map<String, Decimal>();
        for (String classification : ClassificationResult.VALID_CLASSIFICATIONS) {
            scores.put(classification, 0.0);
        }

        // 1. Title-based signals
        if (c != null && String.isNotBlank(c.Title)) {
            applyTitleSignals(c.Title, scores);
        }

        // 2. Interaction pattern signals
        if (summary != null) {
            applyInteractionSignals(summary, scores);
        }

        // 3. Sentiment signals (email tone analysis from subject lines)
        if (summary != null) {
            applySentimentSignals(summary, scores);
        }

        // Find the highest-scoring classification
        String bestClassification = 'Unknown';
        Decimal bestScore = 0.0;
        Decimal totalScore = 0.0;

        for (String classification : scores.keySet()) {
            Decimal score = scores.get(classification);
            totalScore += score;
            if (score > bestScore) {
                bestScore = score;
                bestClassification = classification;
            }
        }

        // Calculate confidence as proportion of total score
        Decimal confidence = totalScore > 0 ? (bestScore / totalScore) : 0.0;

        // If no strong signal, classify as Unknown with low confidence
        if (bestScore < 1.0) {
            bestClassification = 'Unknown';
            confidence = 0.1;
        }

        return new ClassificationResult(bestClassification, confidence, getProviderName());
    }

    private void applyTitleSignals(String title, Map<String, Decimal> scores) {
        String lowerTitle = title.toLowerCase();

        for (String classification : TITLE_KEYWORDS.keySet()) {
            for (String keyword : TITLE_KEYWORDS.get(classification)) {
                if (lowerTitle.contains(keyword)) {
                    scores.put(classification, scores.get(classification) + 3.0);
                    return; // Take first match
                }
            }
        }

        // Manager-level titles suggest Influencer
        if (lowerTitle.contains('manager') || lowerTitle.contains('lead') || lowerTitle.contains('senior')) {
            scores.put('Influencer', scores.get('Influencer') + 2.0);
        }

        // Director/VP without specific match suggests Influencer or Economic Buyer
        if (lowerTitle.contains('director') || lowerTitle.contains('vp') || lowerTitle.contains('vice president')) {
            scores.put('Influencer', scores.get('Influencer') + 2.5);
            scores.put('Economic Buyer', scores.get('Economic Buyer') + 1.5);
        }
    }

    private void applyInteractionSignals(
        InteractionDataService.ContactInteractionSummary summary,
        Map<String, Decimal> scores
    ) {
        // High engagement (many emails + meetings) suggests Champion
        Decimal engagementScore = (summary.emailsSent * 1.0)
            + (summary.emailsReceived * 1.5)
            + (summary.meetingsAttended * 3.0)
            + (summary.tasksCompleted * 1.0);

        if (engagementScore > 20) {
            scores.put('Champion', scores.get('Champion') + 4.0);
        } else if (engagementScore > 10) {
            scores.put('Champion', scores.get('Champion') + 2.0);
            scores.put('Influencer', scores.get('Influencer') + 1.0);
        } else if (engagementScore > 5) {
            scores.put('Influencer', scores.get('Influencer') + 1.5);
        }

        // Very low engagement with negative signals suggests Detractor or Blocker
        if (engagementScore < 3 && summary.meetingsDeclined > 2) {
            scores.put('Blocker', scores.get('Blocker') + 2.0);
            scores.put('Detractor', scores.get('Detractor') + 1.5);
        }

        // Has OpportunityContactRole → strong signal
        if (summary.hasOpportunityRole) {
            if (summary.opportunityRole == 'Decision Maker') {
                scores.put('Economic Buyer', scores.get('Economic Buyer') + 4.0);
            } else if (summary.opportunityRole == 'Evaluator') {
                scores.put('Technical Buyer', scores.get('Technical Buyer') + 3.0);
            } else if (summary.opportunityRole == 'Executive Sponsor') {
                scores.put('Champion', scores.get('Champion') + 3.0);
                scores.put('Economic Buyer', scores.get('Economic Buyer') + 2.0);
            } else if (summary.opportunityRole == 'Influencer') {
                scores.put('Influencer', scores.get('Influencer') + 3.0);
            }
        }

        // High co-occurrence with other key contacts suggests active involvement
        if (summary.coOccurrenceCount > 10) {
            scores.put('Champion', scores.get('Champion') + 1.5);
            scores.put('Influencer', scores.get('Influencer') + 1.0);
        }
    }

    private void applySentimentSignals(
        InteractionDataService.ContactInteractionSummary summary,
        Map<String, Decimal> scores
    ) {
        // Analyze email subjects for negative signals
        if (summary.negativeSignalCount > 3) {
            scores.put('Detractor', scores.get('Detractor') + 3.0);
            scores.put('Blocker', scores.get('Blocker') + 2.0);
        } else if (summary.negativeSignalCount > 1) {
            scores.put('Detractor', scores.get('Detractor') + 1.5);
        }

        // Positive engagement signals
        if (summary.positiveSignalCount > 3) {
            scores.put('Champion', scores.get('Champion') + 2.0);
        }
    }
}
