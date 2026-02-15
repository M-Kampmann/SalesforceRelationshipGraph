/**
 * Fetches values for Contact_Field and Record_Count strength factors
 * using dynamic SOQL. Validates field/object names via Schema describe
 * and enforces FLS with WITH SECURITY_ENFORCED.
 */
public with sharing class CustomFactorDataService {

    /**
     * Fetch custom factor values for a set of contacts.
     * @param contactIds The contacts to fetch data for
     * @param factors Only factors with sourceType Contact_Field or Record_Count
     * @return Map of ContactId to Map of FactorDeveloperName to Decimal value
     */
    public Map<Id, Map<String, Decimal>> fetchCustomFactors(
        Set<Id> contactIds,
        List<StrengthFactorService.StrengthFactor> factors
    ) {
        Map<Id, Map<String, Decimal>> result = new Map<Id, Map<String, Decimal>>();
        for (Id cId : contactIds) {
            result.put(cId, new Map<String, Decimal>());
        }

        if (contactIds.isEmpty() || factors == null || factors.isEmpty()) {
            return result;
        }

        List<StrengthFactorService.StrengthFactor> contactFieldFactors =
            new List<StrengthFactorService.StrengthFactor>();
        List<StrengthFactorService.StrengthFactor> recordCountFactors =
            new List<StrengthFactorService.StrengthFactor>();

        for (StrengthFactorService.StrengthFactor f : factors) {
            if (f.sourceType == 'Contact_Field') {
                contactFieldFactors.add(f);
            } else if (f.sourceType == 'Record_Count') {
                recordCountFactors.add(f);
            }
        }

        if (!contactFieldFactors.isEmpty()) {
            fetchContactFields(contactIds, contactFieldFactors, result);
        }

        for (StrengthFactorService.StrengthFactor f : recordCountFactors) {
            fetchRecordCount(contactIds, f, result);
        }

        return result;
    }

    private void fetchContactFields(
        Set<Id> contactIds,
        List<StrengthFactorService.StrengthFactor> factors,
        Map<Id, Map<String, Decimal>> result
    ) {
        Map<String, Schema.SObjectField> contactFields =
            Schema.SObjectType.Contact.fields.getMap();

        List<String> validFields = new List<String>();
        Map<String, String> fieldToFactorName = new Map<String, String>();

        for (StrengthFactorService.StrengthFactor f : factors) {
            String fieldName = f.sourceValue.toLowerCase();
            if (!contactFields.containsKey(fieldName)) continue;

            Schema.DescribeFieldResult dfr = contactFields.get(fieldName).getDescribe();
            Schema.DisplayType dt = dfr.getType();
            if (dt == Schema.DisplayType.DOUBLE
                || dt == Schema.DisplayType.CURRENCY
                || dt == Schema.DisplayType.INTEGER
                || dt == Schema.DisplayType.PERCENT) {
                validFields.add(f.sourceValue);
                fieldToFactorName.put(fieldName, f.developerName);
            }
        }

        if (validFields.isEmpty()) return;

        String fieldList = 'Id, ' + String.join(validFields, ', ');
        String query = 'SELECT ' + String.escapeSingleQuotes(fieldList)
            + ' FROM Contact WHERE Id IN :contactIds WITH SECURITY_ENFORCED';

        for (SObject record : Database.query(query)) {
            Id contactId = (Id) record.get('Id');
            Map<String, Decimal> contactValues = result.get(contactId);
            if (contactValues == null) continue;

            for (String fieldName : validFields) {
                Object val = record.get(fieldName);
                String factorName = fieldToFactorName.get(fieldName.toLowerCase());
                contactValues.put(factorName, val != null ? (Decimal) val : 0);
            }
        }
    }

    private void fetchRecordCount(
        Set<Id> contactIds,
        StrengthFactorService.StrengthFactor factor,
        Map<Id, Map<String, Decimal>> result
    ) {
        List<String> parts = factor.sourceValue.split('\\.');
        if (parts.size() != 2) return;

        String objectName = parts[0];
        String lookupField = parts[1];

        // Validate object exists
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectName);
        if (sot == null) return;

        // Validate lookup field exists
        Map<String, Schema.SObjectField> fieldMap = sot.getDescribe().fields.getMap();
        if (!fieldMap.containsKey(lookupField.toLowerCase())) return;

        String safeObject = String.escapeSingleQuotes(objectName);
        String safeLookup = String.escapeSingleQuotes(lookupField);

        String query = 'SELECT ' + safeLookup + ' contactRef, COUNT(Id) cnt'
            + ' FROM ' + safeObject
            + ' WHERE ' + safeLookup + ' IN :contactIds'
            + ' WITH SECURITY_ENFORCED'
            + ' GROUP BY ' + safeLookup;

        for (AggregateResult ar : Database.query(query)) {
            Id contactId = (Id) ar.get('contactRef');
            Integer count = (Integer) ar.get('cnt');
            Map<String, Decimal> contactValues = result.get(contactId);
            if (contactValues != null) {
                contactValues.put(factor.developerName, count);
            }
        }
    }
}
