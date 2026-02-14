/**
 * Data class representing the result of a contact classification.
 */
public class ClassificationResult {

    @AuraEnabled public String classification { get; set; }
    @AuraEnabled public Decimal confidenceScore { get; set; }
    @AuraEnabled public String providerName { get; set; }
    @AuraEnabled public Boolean isUserOverride { get; set; }

    public ClassificationResult() {
        this.classification = 'Unknown';
        this.confidenceScore = 0.0;
        this.isUserOverride = false;
    }

    public ClassificationResult(String classification, Decimal confidenceScore, String providerName) {
        this.classification = classification;
        this.confidenceScore = confidenceScore;
        this.providerName = providerName;
        this.isUserOverride = false;
    }

    /**
     * Valid classification values.
     */
    public static final Set<String> VALID_CLASSIFICATIONS = new Set<String>{
        'Champion', 'Economic Buyer', 'Technical Buyer', 'Blocker',
        'Influencer', 'End User', 'Detractor', 'Unknown'
    };

    public Boolean isValid() {
        return VALID_CLASSIFICATIONS.contains(this.classification)
            && this.confidenceScore >= 0.0
            && this.confidenceScore <= 1.0;
    }
}
