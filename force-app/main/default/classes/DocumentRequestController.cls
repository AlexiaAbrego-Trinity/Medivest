public with sharing class DocumentRequestController {

    // =========================
    // DTOs for LWC compatibility
    // =========================

    public class OptionDTO implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public OptionDTO(String label, String value) {
            this.label = label;
            this.value = value;
        }
        public Integer compareTo(Object other) {
            OptionDTO otherOption = (OptionDTO) other;
            return this.label.compareTo(otherOption.label);
        }
    }

    public class TemplateDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        public TemplateDTO(String id, String name) {
            this.id = id;
            this.name = name;
        }
    }

    // =========================
    // Simple Support Classes (for LWC compatibility)
    // =========================
    public class DocumentRuleInfo {
        @AuraEnabled public String templateFieldApi;
        @AuraEnabled public String checkboxFieldApi;
        @AuraEnabled public String templateContent;
        @AuraEnabled public List<DocumentRuleOption> options;
    }

    public class DocumentRuleOption {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean affectsCheckbox;
    }

    // =========================
    // PRODUCTION SUPPORT CLASSES (EXACT FROM MATT'S CODE)
    // =========================
    public class DocFetchResult {
        @AuraEnabled public List<webm__Webmerge_Mapping__c> rows;
        @AuraEnabled public List<DeptResolution> resolutions;
        @AuraEnabled public String queryInfo;
    }
    
    public class DeptResolution {
        @AuraEnabled public String input;          // what client sent
        @AuraEnabled public String resolvedValue;  // canonical picklist value used in SOQL (exact, not trimmed)
        @AuraEnabled public String resolvedLabel;  // picklist label
        @AuraEnabled public Boolean matched;
        @AuraEnabled public String reason;
    }

    // =========================
    // SECURITY CHECKS
    // =========================
    private static void assertReadableWebmergeMapping() {
        Schema.DescribeSObjectResult d = webm__Webmerge_Mapping__c.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            throw new AuraHandledException('You do not have access to Webmerge Mappings.');
        }
    }

    // =========================
    // STEP 1: Departments (EXACT PRODUCTION CODE)
    // =========================
    /**
     * Department picklist (labels) from webm__Webmerge_Mapping__c.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> fetchDepartments() {
        List<String> values = new List<String>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get('webm__Webmerge_Mapping__c');
        if (objType == null) return values;
        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey('Department__c')) return values;
        for (Schema.PicklistEntry p : fieldMap.get('Department__c').getDescribe().getPicklistValues()) {
            if (p != null && p.isActive()) values.add(p.getLabel());
        }
        values.sort();
        return values;
    }

    // =========================
    // STEP 2: SubDepartments (EXACT PRODUCTION CODE)
    // =========================
    /**
     * (Optional) Sub_Department picklist (labels) if using native field.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> fetchSubDepartments() {
        List<String> values = new List<String>();
        Schema.SObjectType objType = Schema.getGlobalDescribe().get('webm__Webmerge_Mapping__c');
        if (objType == null) return values;
        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey('Sub_Department__c')) return values;
        for (Schema.PicklistEntry p : fieldMap.get('Sub_Department__c').getDescribe().getPicklistValues()) {
            if (p != null && p.isActive()) values.add(p.getLabel());
        }
        values.sort();
        return values;
    }

    /**
     * Filtered sub-departments: returns only sub-departments that have active documents
     * in the specified department
     */
    @AuraEnabled
    public static List<String> fetchSubDepartmentsByDepartment(String department) {
        List<String> values = new List<String>();
        if (String.isBlank(department)) return values;

        // Check object access
        Schema.DescribeSObjectResult d = webm__Webmerge_Mapping__c.SObjectType.getDescribe();
        if (!d.isAccessible()) return values;

        // Query distinct sub-departments that exist for this department with active templates
        List<AggregateResult> results = [
            SELECT Sub_Department__c subDept
            FROM webm__Webmerge_Mapping__c
            WHERE Department__c = :department
              AND webm__Active__c = true
              AND webm__save_file__c = true
              AND Sub_Department__c != null
            GROUP BY Sub_Department__c
            ORDER BY Sub_Department__c
        ];

        for (AggregateResult ar : results) {
            String subDept = (String)ar.get('subDept');
            if (String.isNotBlank(subDept)) {
                values.add(subDept);
            }
        }

        return values;
    }



    // =========================
    // STEP 3: Global Search (EXACT PRODUCTION CODE)
    // =========================
    @AuraEnabled(cacheable=true)
    public static List<webm__Webmerge_Mapping__c> searchMappingsByName(String term) {
        if (String.isBlank(term)) return new List<webm__Webmerge_Mapping__c>();
        Schema.DescribeSObjectResult d = webm__Webmerge_Mapping__c.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            throw new AuraHandledException('You do not have access to Formstack Mappings.');
        }
        String likeTerm = '%' + String.escapeSingleQuotes(term.trim()) + '%';
        return [
            SELECT Id, Name, webm__Webmerge_Document_Key__c, webm__Webmerge_Document_Id__c,
                   Department__c, Sub_Department__c
            FROM webm__Webmerge_Mapping__c
            WHERE Name LIKE :likeTerm
            ORDER BY Name
            LIMIT 500
        ];
    }

    // =========================
    // DEPARTMENT RESOLUTION HELPERS (EXACT PRODUCTION CODE)
    // =========================
    /**
     * Build a map of Department__c picklist VALUE -> entry.
     * IMPORTANT: preserve value EXACTLY as defined (no trim).
     */
    private static Map<String, Schema.PicklistEntry> getDeptPicklistByValue() {
        Schema.SObjectType objType = Schema.getGlobalDescribe().get('webm__Webmerge_Mapping__c');
        if (objType == null) return new Map<String, Schema.PicklistEntry>();
        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();
        if (!fieldMap.containsKey('Department__c')) return new Map<String, Schema.PicklistEntry>();
        Map<String, Schema.PicklistEntry> byValue = new Map<String, Schema.PicklistEntry>();
        for (Schema.PicklistEntry p : fieldMap.get('Department__c').getDescribe().getPicklistValues()) {
            if (p != null && p.isActive()) {
                byValue.put(p.getValue(), p); // DO NOT TRIM
            }
        }
        return byValue;
    }

    /**
     * Resolve a user-provided department (label or value) to the exact picklist value.
     */
    private static DeptResolution resolveDept(String inputRaw) {
        DeptResolution r = new DeptResolution();
        r.input = inputRaw;
        if (String.isBlank(inputRaw)) {
            r.matched = false;
            r.reason  = 'Blank department name.';
            return r;
        }
        String inTrim = inputRaw.trim();
        Map<String, Schema.PicklistEntry> byValue = getDeptPicklistByValue();
        // Direct value match
        if (byValue.containsKey(inTrim)) {
            Schema.PicklistEntry pe = byValue.get(inTrim);
            r.resolvedValue = pe.getValue();
            r.resolvedLabel = pe.getLabel();
            r.matched = true;
            r.reason  = 'Matched by value.';
            return r;
        }
        // Case-insensitive label match
        for (Schema.PicklistEntry pe : byValue.values()) {
            if (pe.getLabel() != null && pe.getLabel().trim().equalsIgnoreCase(inTrim)) {
                r.resolvedValue = pe.getValue();
                r.resolvedLabel = pe.getLabel();
                r.matched = true;
                r.reason  = 'Matched by label.';
                return r;
            }
        }
        r.matched = false;
        r.reason  = 'No picklist match for input.';
        return r;
    }

    // =========================
    // STEP 4: Documents by Dept/Sub (EXACT PRODUCTION CODE)
    // =========================
    /**
     * Unified fetch: accepts labels or values, single or multi.
     * Supports multi Sub-Department names (keyword union).
     */
    @AuraEnabled(cacheable=true)
    public static DocFetchResult fetchDocumentsUnified(List<String> departmentInputs, List<String> subDepartmentNames) {
        DocFetchResult out = new DocFetchResult();
        out.rows = new List<webm__Webmerge_Mapping__c>();
        out.resolutions = new List<DeptResolution>();
        if (departmentInputs == null || departmentInputs.isEmpty()) {
            out.queryInfo = 'No departments provided.';
            return out;
        }
        // Resolve to canonical picklist values
        Set<String> resolvedValues = new Set<String>();
        for (String dep : departmentInputs) {
            DeptResolution dr = resolveDept(dep);
            out.resolutions.add(dr);
            if (dr.matched) resolvedValues.add(dr.resolvedValue);
        }
        if (resolvedValues.isEmpty()) {
            out.queryInfo = 'No valid departments resolved.';
            return out;
        }
        // Access check
        Schema.DescribeSObjectResult d = webm__Webmerge_Mapping__c.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            throw new AuraHandledException('You do not have access to Formstack Mappings.');
        }
        // Base query
        List<webm__Webmerge_Mapping__c> base = [
            SELECT Id, Name, webm__Webmerge_Document_Key__c, webm__Webmerge_Document_Id__c,
                   Department__c, Sub_Department__c
            FROM webm__Webmerge_Mapping__c
            WHERE Department__c IN :resolvedValues
            ORDER BY Department__c, Name
        ];
        // If SubDept is null/empty or contains "All" → no keyword filter
        Boolean useAll = (subDepartmentNames == null || subDepartmentNames.isEmpty() ||
                          (new List<String>(subDepartmentNames)).contains('All'));
        if (useAll) {
            out.rows = base;
            out.queryInfo = 'Department__c IN [' + String.join(new List<String>(resolvedValues), ', ') + ']; Sub=All';
            return out;
        }
        // Build union of keywords from all requested Sub Departments
        Set<String> kwSet = new Set<String>();
        for (String sd : subDepartmentNames) {
            List<String> kws = getKeywordsForSub(sd);
            for (String k : kws) if (!String.isBlank(k)) kwSet.add(k.toLowerCase());
        }
        if (kwSet.isEmpty()) {
            out.rows = base;
            out.queryInfo = 'Department__c IN [' + String.join(new List<String>(resolvedValues), ', ') + ']; Sub had no keywords.';
            return out;
        }
        // Filter by union of keywords (matches Name)
        List<webm__Webmerge_Mapping__c> filtered = new List<webm__Webmerge_Mapping__c>();
        for (webm__Webmerge_Mapping__c r : base) {
            String nameLower = (r.Name != null) ? r.Name.toLowerCase() : '';
            Boolean match = false;
            for (String kw : kwSet) {
                if (nameLower.contains(kw)) { match = true; break; }
            }
            if (match) filtered.add(r);
        }
        out.rows = filtered;
        out.queryInfo = 'Department__c IN [' + String.join(new List<String>(resolvedValues), ', ') + ']; Sub in [' + String.join(new List<String>(subDepartmentNames), ', ') + ']; Keywords=' + String.join(new List<String>(kwSet), ', ');
        return out;
    }

    // =========================
    // Sub-department keywords (EXACT PRODUCTION CODE)
    // =========================
    private static List<String> getKeywordsForSub(String subDepartment) {
        Map<String, List<String>> mapKW = new Map<String, List<String>>{
            'Cover Letters'                => new List<String>{'cover', 'letter'},
            'Email Templates'              => new List<String>{'email', 'template'},
            'Recommendation Packages'      => new List<String>{'recommendation', 'package'},
            'Releases'                     => new List<String>{'release'},
            'Reports'                      => new List<String>{'report'},
            'Authorizations'               => new List<String>{'authorization'},
            'BCN/Quotes'                   => new List<String>{'bcn', 'quote', 'claim'},
            'Benefits Explanation'         => new List<String>{'benefit', 'explanation'},
            'Refunds'                      => new List<String>{'refund'},
            'Trust Disbursement Requests'  => new List<String>{'trust', 'disbursement', 'request'},
            'BCRC'                         => new List<String>{'bcrc'},
            'CRC'                          => new List<String>{'crc'},
            'LOAs'                         => new List<String>{'loa'},
            'Activation Checklists'        => new List<String>{'activation', 'checklist'},
            'Agreements'                   => new List<String>{'agreement'},
            'Invoices'                     => new List<String>{'invoice'},
            'Activation'                   => new List<String>{'activation'},
            'Activity Report'              => new List<String>{'activity', 'report'},
            'Attestation'                  => new List<String>{'attestation'},
            'Exhaustions'                  => new List<String>{'exhaustion'},
            'ID Card'                      => new List<String>{'id', 'card'},
            'Pharmacy'                     => new List<String>{'pharmacy'},
            'Reactivations'                => new List<String>{'reactivation'},
            'Unable to Reach'              => new List<String>{'unable', 'reach'},
            'Welcome Kits'                 => new List<String>{'welcome', 'kits'},
            'Referral Form'                => new List<String>{'referral', 'form'}
        };
        return mapKW.containsKey(subDepartment) ? mapKW.get(subDepartment) : new List<String>();
    }

    // =========================
    // DOCUMENT GENERATION (EXACT PRODUCTION CODE)
    // =========================
    @AuraEnabled
    public static Id mergeWithMapping(Id mappingId, Id recordId, String objectApiName) {
        if (mappingId == null || recordId == null || String.isBlank(objectApiName)) {
            throw new AuraHandledException('Missing mappingId, recordId, or objectApiName.');
        }

        // 🚨 TRINITY WEBMERGE DEBUG: Log what Apex receives from LWC
        System.debug('🚀 TRINITY WEBMERGE DEBUG: mergeWithMapping called with:');
        System.debug('📦 Parameters received:');
        System.debug('  - mappingId: ' + mappingId);
        System.debug('  - recordId: ' + recordId);
        System.debug('  - objectApiName: ' + objectApiName);

        // 🚨 MATT'S DEBUG: Edison Template Detection and Field Validation
        // Check if this is an Edison template by querying the mapping
        webm__Webmerge_Mapping__c mapping = [
            SELECT Id, Name
            FROM webm__Webmerge_Mapping__c
            WHERE Id = :mappingId
            LIMIT 1
        ];

        Boolean isEdisonTemplate = (mapping.Name != null &&
            mapping.Name.toLowerCase().contains('edison'));

        if (isEdisonTemplate) {
            System.debug('🔥 EDISON DEBUG: Edison template detected in mergeWithMapping!');
            System.debug('📋 Template Name: ' + mapping.Name);
            System.debug('🎯 EDISON DEBUG: About to validate trm_Edison_Template__c field before webmerge');

            // Query the Case to verify Edison field is populated BEFORE webmerge
            try {
                Case edisonCase = [
                    SELECT Id, trm_Edison_Template__c, trm_Edison_Checkbox__c
                    FROM Case
                    WHERE Id = :recordId
                    LIMIT 1
                ];

                System.debug('🔍 EDISON FIELD VALIDATION BEFORE WEBMERGE:');
                System.debug('  - Case ID: ' + edisonCase.Id);
                System.debug('  - trm_Edison_Template__c populated: ' + (edisonCase.trm_Edison_Template__c != null));
                if (edisonCase.trm_Edison_Template__c != null) {
                    System.debug('  - Field length: ' + edisonCase.trm_Edison_Template__c.length() + ' characters');
                    String preview = edisonCase.trm_Edison_Template__c.length() > 100 ?
                        edisonCase.trm_Edison_Template__c.substring(0, 100) + '...' :
                        edisonCase.trm_Edison_Template__c;
                    System.debug('  - Content preview: "' + preview + '"');
                } else {
                    System.debug('  - ❌ CRITICAL: trm_Edison_Template__c is NULL before webmerge!');
                }
                System.debug('  - trm_Edison_Checkbox__c: ' + edisonCase.trm_Edison_Checkbox__c);
                System.debug('🚀 EDISON DEBUG: Field validation complete - proceeding with webmerge');

            } catch (Exception e) {
                System.debug('❌ EDISON DEBUG: Failed to query Edison fields: ' + e.getMessage());
            }
        }

        try {
            System.debug('🔄 TRINITY WEBMERGE DEBUG: About to call webm.WebmergeGenerator.generateDocument');
            System.debug('📤 WebmergeGenerator parameters:');
            System.debug('  - mappingId (as String): ' + String.valueOf(mappingId));
            System.debug('  - recordId (as String): ' + String.valueOf(recordId));
            System.debug('  - objectApiName: ' + objectApiName);

            webm.WebmergeGenerator.generateDocument(
                String.valueOf(mappingId),
                String.valueOf(recordId),
                objectApiName
            );

            System.debug('✅ TRINITY WEBMERGE DEBUG: webm.WebmergeGenerator.generateDocument completed');
            System.debug('🔍 TRINITY WEBMERGE DEBUG: Querying for generated ContentDocumentLink...');

            List<ContentDocumentLink> links = [
                SELECT ContentDocumentId
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :recordId
                ORDER BY SystemModstamp DESC
                LIMIT 1
            ];

            System.debug('📄 TRINITY WEBMERGE DEBUG: ContentDocumentLink query results:');
            System.debug('  - Links found: ' + links.size());
            if (!links.isEmpty()) {
                System.debug('  - Latest ContentDocumentId: ' + links[0].ContentDocumentId);
            } else {
                System.debug('  - No ContentDocumentLinks found for recordId: ' + recordId);
            }

            Id resultDocId = links.isEmpty() ? null : links[0].ContentDocumentId;
            System.debug('🎯 TRINITY WEBMERGE DEBUG: Returning ContentDocumentId: ' + resultDocId);

            return resultDocId;
        } catch (Exception e) {
            throw new AuraHandledException('Formstack merge failed: ' + e.getMessage());
        }
    }

    // =========================
    // DOC_RULES SUPPORT (for advanced documents)
    // =========================
    // DOC_RULES handled in JavaScript - no server-side rule processing needed

    // Simple enhanced generation - just calls production mergeWithMapping
    @AuraEnabled
    public static Id generateWithEnhancedFeatures(Id mappingId, Id recordId, String templateContent, String targetFieldApi, String checkboxFieldApi, Boolean checkboxValue) {
        // For now, just use the production method - LWC handles field updates separately
        return mergeWithMapping(mappingId, recordId, 'Case');
    }

    @AuraEnabled
    public static void updateCaseTemplateFields(
        Id caseId,
        String targetFieldApi,
        String value,
        String checkboxFieldApi,
        Boolean checkboxValue
    ) {
        // 🚨 MATT'S DEBUG: Edison Template Field Population Validation
        System.debug('🎯 EDISON DEBUG: updateCaseTemplateFields called');
        System.debug('📋 Parameters:');
        System.debug('  - caseId: ' + caseId);
        System.debug('  - targetFieldApi: ' + targetFieldApi);
        System.debug('  - value length: ' + (value != null ? value.length() : 0) + ' characters');
        System.debug('  - checkboxFieldApi: ' + checkboxFieldApi);
        System.debug('  - checkboxValue: ' + checkboxValue);

        // Special Edison template detection
        Boolean isEdisonTemplate = (targetFieldApi == 'trm_Edison_Template__c');
        if (isEdisonTemplate) {
            System.debug('🔥 EDISON TEMPLATE DETECTED! Processing trm_Edison_Template__c field');
            System.debug('📝 Edison Template Content Preview:');
            if (value != null && value.length() > 0) {
                String preview = value.length() > 100 ? value.substring(0, 100) + '...' : value;
                System.debug('  Content: "' + preview + '"');
                System.debug('  Full length: ' + value.length() + ' characters');
            } else {
                System.debug('  ⚠️ WARNING: Edison template content is null or empty!');
            }
        }

        if (caseId == null || String.isBlank(targetFieldApi)) {
            throw new AuraHandledException('Missing caseId or targetFieldApi.');
        }
        Schema.DescribeSObjectResult caseDescribe = Case.SObjectType.getDescribe();
        if (!caseDescribe.isAccessible()) throw new AuraHandledException('You do not have access to Case.');
        Map<String, Schema.SObjectField> fieldMap = caseDescribe.fields.getMap();
        if (!fieldMap.containsKey(targetFieldApi)) {
            throw new AuraHandledException('Target field not found on Case: ' + targetFieldApi);
        }
        if (!fieldMap.get(targetFieldApi).getDescribe().isUpdateable()) {
            throw new AuraHandledException('Target field is not updateable: ' + targetFieldApi);
        }

        // 🚨 MATT'S DEBUG: Pre-update field validation
        System.debug('🔍 EDISON DEBUG: About to update Case fields');

        Case caseRecord = new Case(Id = caseId);
        caseRecord.put(targetFieldApi, value);
        if (String.isNotBlank(checkboxFieldApi)) {
            if (!fieldMap.containsKey(checkboxFieldApi)) {
                throw new AuraHandledException('Checkbox field not found on Case: ' + checkboxFieldApi);
            }
            if (!fieldMap.get(checkboxFieldApi).getDescribe().isUpdateable()) {
                throw new AuraHandledException('Checkbox field is not updateable: ' + checkboxFieldApi);
            }
            caseRecord.put(checkboxFieldApi, checkboxValue);
        }

        // 🚨 MATT'S DEBUG: Execute the update
        System.debug('💾 EDISON DEBUG: Executing Case update...');
        update caseRecord;
        System.debug('✅ EDISON DEBUG: Case update completed successfully');

        // 🚨 MATT'S DEBUG: Post-update validation - CRITICAL FOR EDISON TROUBLESHOOTING
        if (isEdisonTemplate) {
            System.debug('🔍 EDISON DEBUG: Post-update validation - querying Case to verify field population');

            // Query the Case to verify the field was actually populated
            String queryFields = 'Id, ' + targetFieldApi;
            if (String.isNotBlank(checkboxFieldApi)) {
                queryFields += ', ' + checkboxFieldApi;
            }

            String soql = 'SELECT ' + queryFields + ' FROM Case WHERE Id = :caseId LIMIT 1';
            List<Case> verificationCases = Database.query(soql);

            if (!verificationCases.isEmpty()) {
                Case verifiedCase = verificationCases[0];
                Object fieldValue = verifiedCase.get(targetFieldApi);

                System.debug('🎯 EDISON FIELD VERIFICATION RESULTS:');
                System.debug('  - Case ID: ' + verifiedCase.Id);
                System.debug('  - Field API: ' + targetFieldApi);
                System.debug('  - Field populated: ' + (fieldValue != null));
                if (fieldValue != null) {
                    String fieldValueStr = String.valueOf(fieldValue);
                    System.debug('  - Field length: ' + fieldValueStr.length() + ' characters');
                    String fieldPreview = fieldValueStr.length() > 100 ? fieldValueStr.substring(0, 100) + '...' : fieldValueStr;
                    System.debug('  - Field content preview: "' + fieldPreview + '"');
                } else {
                    System.debug('  - ❌ CRITICAL: Edison template field is NULL after update!');
                }

                if (String.isNotBlank(checkboxFieldApi)) {
                    Object checkboxFieldValue = verifiedCase.get(checkboxFieldApi);
                    System.debug('  - Checkbox field: ' + checkboxFieldApi + ' = ' + checkboxFieldValue);
                }

                System.debug('🚀 EDISON DEBUG: Field validation complete - ready for webmerge payload');
            } else {
                System.debug('❌ EDISON DEBUG: Could not query Case for verification!');
            }
        }
    }

    // =========================
    // AGENT FIELDS SUPPORT (multi-object)
    // =========================

    /**
     * Generic method to update agent fields on any object that has them
     * Supports Case, Member_Account__c, Administration__c, Denied_Refund__c, Entity__c
     */
    @AuraEnabled
    public static void updateAgentFields(Id recordId) {
        if (recordId == null) {
            throw new AuraHandledException('Missing record Id.');
        }

        // Get object type dynamically
        String objectApiName = recordId.getSObjectType().getDescribe().getName();
        Schema.DescribeSObjectResult objectDescribe = Schema.getGlobalDescribe().get(objectApiName).getDescribe();

        if (!objectDescribe.isAccessible()) {
            throw new AuraHandledException('You do not have access to ' + objectApiName + '.');
        }

        Map<String, Schema.SObjectField> fieldMap = objectDescribe.fields.getMap();

        // Agent field API names
        String fnApi = 'trm_Agent_Name__c';
        String lnApi = 'trm_Agent_Last_Name__c';
        String exApi = 'trm_Agent_Extension__c';
        String ttApi = 'trm_Agent_Title__c';

        // Get current user information
        User currentUser = [
            SELECT Id, FirstName, LastName, Name, Title, Extension
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];

        // Parse user information
        String firstName = (currentUser.FirstName != null) ? currentUser.FirstName : parseFirstName(currentUser.Name);
        String lastName = (currentUser.LastName != null) ? currentUser.LastName : parseLastName(currentUser.Name);
        String extension = parseExtension(currentUser.Extension);
        String title = currentUser.Title;

        // Create generic SObject record for update
        SObject record = Schema.getGlobalDescribe().get(objectApiName).newSObject(recordId);

        // Update fields if they exist and are updateable
        if (fieldMap.containsKey(fnApi) && fieldMap.get(fnApi).getDescribe().isUpdateable()) {
            record.put(fnApi, firstName);
        }
        if (fieldMap.containsKey(lnApi) && fieldMap.get(lnApi).getDescribe().isUpdateable()) {
            record.put(lnApi, lastName);
        }
        if (fieldMap.containsKey(exApi) && fieldMap.get(exApi).getDescribe().isUpdateable()) {
            record.put(exApi, extension);
        }
        if (fieldMap.containsKey(ttApi) && fieldMap.get(ttApi).getDescribe().isUpdateable()) {
            record.put(ttApi, title);
        }

        update record;
    }

    // =========================
    // HELPER METHODS (from production)
    // =========================

    private static String parseFirstName(String fullName) {
        if (String.isBlank(fullName)) return null;
        List<String> parts = fullName.trim().split('\\s+');
        return (parts.isEmpty()) ? null : parts[0];
    }

    private static String parseLastName(String fullName) {
        if (String.isBlank(fullName)) return null;
        List<String> parts = fullName.trim().split('\\s+');
        if (parts.size() <= 1) return null;
        parts.remove(0);
        return String.join(parts, ' ');
    }

    private static String parseExtension(String phone) {
        if (String.isBlank(phone)) return null;
        Pattern p = Pattern.compile('(?i)(?:ext|x)\\s*(\\d+)');
        Matcher m = p.matcher(phone);
        if (m.find()) return m.group(1);
        return null;
    }

    // ====== DOWNLOAD-IMMEDIATE SUPPORT ======
    public class DownloadPayloadDTO {
        @AuraEnabled public String fileName;
        @AuraEnabled public String mimeType;
        @AuraEnabled public String base64Data;
        @AuraEnabled public Id contentDocumentId;
        @AuraEnabled public Id contentVersionId;
        public DownloadPayloadDTO(String n, String m, String b64, Id docId, Id verId) {
            fileName = n; mimeType = m; base64Data = b64;
            contentDocumentId = docId; contentVersionId = verId;
        }
    }

    @AuraEnabled
    public static DownloadPayloadDTO mergeAndReturnFile(Id mappingId, Id recordId, String objectApiName) {
        Id docId = mergeWithMapping(mappingId, recordId, objectApiName);
        if (docId == null) {
            throw new AuraHandledException('Generated document not found to download.');
        }

        ContentVersion cv = [
            SELECT Id, Title, FileExtension, VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :docId
            ORDER BY VersionNumber DESC
            LIMIT 1
        ];

        String ext  = (cv.FileExtension != null) ? cv.FileExtension.toLowerCase() : 'pdf';
        String name = (cv.Title != null ? cv.Title : 'document') + '.' + ext;

        String mime =
            (ext == 'pdf')  ? 'application/pdf' :
            (ext == 'docx') ? 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' :
            (ext == 'doc')  ? 'application/msword' :
            (ext == 'xlsx') ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' :
            (ext == 'png')  ? 'image/png' :
            (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' :
            'application/octet-stream';

        String b64 = EncodingUtil.base64Encode(cv.VersionData);
        return new DownloadPayloadDTO(name, mime, b64, docId, cv.Id);
    }
    // ====== /DOWNLOAD-IMMEDIATE SUPPORT ======

    /**
     * Fetch related Supporting_Claims__c records for the current parent record.
     * Adjust the WHERE clause (Allocation__c) to the correct lookup field if needed.
     */
    @AuraEnabled(cacheable=true)
    public static List<Supporting_Claims__c> fetchClaims(Id parentId) {
        if (parentId == null) {
            return new List<Supporting_Claims__c>();
        }

        // TODO: adjust relationship field (Allocation__c, Case__c, etc.) based on your data model
        return [
            SELECT Id,
                Name,
                Date_of_Injury__c,
                Accepted_Claimed__c,
                Denied__c
            FROM Supporting_Claims__c
            WHERE Allocation__c = :parentId
            ORDER BY CreatedDate DESC
        ];
    }

    /**
     * Persist the list of selected claim Ids into a text field on the parent record
     * so Formstack/WebMerge can consume them with an IN (...) clause.
     */
    @AuraEnabled
    public static void updateSelectedClaims(Id recordId, List<Id> claimIds) {
        if (recordId == null) {
            throw new AuraHandledException('Missing recordId.');
        }

        // Normaliza lista nula
        if (claimIds == null) {
            claimIds = new List<Id>();
        }

        Set<Id> selectedIds = new Set<Id>(claimIds);

        // 1) Traemos TODOS los claims de ese Allocation / Case
        List<Supporting_Claims__c> claims = [
            SELECT Id, trm_Selected_For_Carrier_Letter__c
            FROM Supporting_Claims__c
            WHERE Allocation__c = :recordId
        ];

        List<Supporting_Claims__c> toUpdate = new List<Supporting_Claims__c>();

        for (Supporting_Claims__c sc : claims) {
            Boolean shouldBeSelected = selectedIds.contains(sc.Id);

            // Solo actualizamos si cambió (para no hacer DML de más)
            if (sc.trm_Selected_For_Carrier_Letter__c != shouldBeSelected) {
                sc.trm_Selected_For_Carrier_Letter__c = shouldBeSelected;
                toUpdate.add(sc);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }




}