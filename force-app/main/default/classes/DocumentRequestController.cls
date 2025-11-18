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


    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> fetchPayeeAddresses(Id caseId) {
        List<OptionDTO> out = new List<OptionDTO>();
        if (caseId == null) return out;

        Case c = [
            SELECT Id,
                Payee_Name__c,
                Payee_Address__r.Address__c
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        // Billing (Case.Payee_Address__r.Address__c)
        if (c.Payee_Address__r != null && c.Payee_Address__r.Address__c != null) {
            System.Address a = c.Payee_Address__r.Address__c;
            String billingVal = formatAddress(a.street, a.city, a.state, a.postalCode, a.country);
            if (!String.isBlank(billingVal)) {
                out.add(new OptionDTO('Billing - ' + billingVal.replace('\n', ' '), billingVal));
            }
        }

        // Mailing / Main desde Account (Payee_Name__c)
        if (c.Payee_Name__c != null) {
            Account acc = [
                SELECT Id, Name,
                    BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                    ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
                FROM Account
                WHERE Id = :c.Payee_Name__c
                LIMIT 1
            ];

            String mailing = formatAddress(
                acc.BillingStreet, acc.BillingCity, acc.BillingState, acc.BillingPostalCode, acc.BillingCountry
            );
            if (!String.isBlank(mailing)) {
                out.add(new OptionDTO('Mailing - ' + mailing.replace('\n', ' '), mailing));
            }

            String mainPhysical = formatAddress(
                acc.ShippingStreet, acc.ShippingCity, acc.ShippingState, acc.ShippingPostalCode, acc.ShippingCountry
            );
            if (!String.isBlank(mainPhysical)) {
                out.add(new OptionDTO('Main/Physical - ' + mainPhysical.replace('\n', ' '), mainPhysical));
            }
        }

        return out;
    }

        private static String formatAddress(String street, String city, String state, String postal, String country) {
        // Join non-blank parts into a human-readable multiline address
        List<String> line1 = new List<String>();
        if (!String.isBlank(street)) line1.add(street);

        List<String> line2 = new List<String>();
        if (!String.isBlank(city))   line2.add(city);
        if (!String.isBlank(state))  line2.add(state);
        if (!String.isBlank(postal)) line2.add(postal);

        List<String> parts = new List<String>();
        if (!line1.isEmpty()) parts.add(String.join(line1, ', '));
        if (!line2.isEmpty()) parts.add(String.join(line2, ' '));
        if (!String.isBlank(country)) parts.add(country);

        return String.join(parts, '\n');
    }

    // Small helper class used by parseFormattedAddress
    private class AddressParts {
        String street;
        String city;
        String state;
        String postal;
    }

    /**
     * Parses the formatted address created by formatAddress().
     */
    private static AddressParts parseFormattedAddress(String formatted) {
        AddressParts ap = new AddressParts();
        if (String.isBlank(formatted)) return ap;

        List<String> lines = formatted.split('\\n');

        if (!lines.isEmpty()) {
            String l1 = lines[0];
            ap.street = (l1 != null) ? l1.trim() : null;
        }

        if (lines.size() >= 2) {
            String line2Raw = lines[1];
            String line2 = (line2Raw != null) ? line2Raw.trim() : '';

            Pattern p = Pattern.compile('^\\s*([^,]+?)(?:,)?\\s+([A-Za-z]{2,})\\s+(\\S+)\\s*$');
            Matcher m = p.matcher(line2);
            if (m.matches()) {
                String g1 = m.group(1);
                String g2 = m.group(2);
                String g3 = m.group(3);
                ap.city   = (g1 != null) ? g1.trim() : null;
                ap.state  = (g2 != null) ? g2.trim() : null;
                ap.postal = (g3 != null) ? g3.trim() : null;
            } else {
                List<String> tokens = (line2 == null) ? new List<String>() : line2.split('\\s+');
                if (tokens.size() >= 3) {
                    ap.state  = tokens[tokens.size()-2];
                    ap.postal = tokens[tokens.size()-1];
                    List<String> cityParts = new List<String>();
                    for (Integer i = 0; i < tokens.size()-2; i++) cityParts.add(tokens[i]);
                    ap.city = String.join(cityParts, ' ');
                } else if (line2 != null && line2.contains(',')) {
                    List<String> parts = line2.split(',', 2);
                    ap.city = (parts.size() > 0 && parts[0] != null) ? parts[0].trim() : null;

                    String right = (parts.size() > 1) ? parts[1] : null;
                    List<String> rightTokens = (right == null) ? new List<String>() : right.trim().split('\\s+');
                    if (rightTokens.size() >= 2) {
                        ap.state  = rightTokens[0];
                        ap.postal = rightTokens[1];
                    }
                } else {
                    ap.city = line2;
                }
            }
        }
        return ap;
    }

    /*@AuraEnabled
    public static void setCaseAddress(Id caseId, String address) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');
        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();

        final String STREET_API  = 'trm_Address_Street__c';
        final String CITY_API    = 'trm_Address_City__c';
        final String STATE_API   = 'trm_Address_State__c';
        final String POSTAL_API  = 'trm_Address_PostalCode__c';

        for (String api : new List<String>{STREET_API, CITY_API, STATE_API, POSTAL_API}) {
            if (!fmap.containsKey(api)) {
                throw new AuraHandledException('Field ' + api + ' not found on Case.');
            }
            if (!fmap.get(api).getDescribe().isUpdateable()) {
                throw new AuraHandledException('No FLS to update ' + api + '.');
            }
        }

        if (String.isBlank(address)) {
            Case clearC = new Case(
                Id = caseId,
                trm_Address_Street__c     = null,
                trm_Address_City__c       = null,
                trm_Address_State__c      = null,
                trm_Address_PostalCode__c = null
            );
            update clearC;
            return;
        }

        AddressParts parts = parseFormattedAddress(address);

        Case c = new Case(Id = caseId);
        c.put(STREET_API, parts.street);
        c.put(CITY_API,   parts.city);
        c.put(STATE_API,  parts.state);
        c.put(POSTAL_API, parts.postal);
        update c;
    }*/
    
    @AuraEnabled
    public static void setCaseAddress(Id caseId, String address) {
        if (caseId == null) {
            throw new AuraHandledException('Missing caseId.');
        }

        // Object-level security
        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            throw new AuraHandledException('No access to Case.');
        }

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();

        // Compound Address subfields for trm_Document_Address__c
        final String STREET_API     = 'trm_Document_Address__Street__s';
        final String CITY_API       = 'trm_Document_Address__City__s';
        final String STATECODE_API  = 'trm_Document_Address__StateCode__s';
        final String POSTAL_API     = 'trm_Document_Address__PostalCode__s';
        final String COUNTRY_API    = 'trm_Document_Address__CountryCode__s';

        // Ensure compound address subfields exist and are updateable
        for (String api : new List<String>{
            STREET_API,
            CITY_API,
            STATECODE_API,
            POSTAL_API,
            COUNTRY_API
        }) {
            if (!fmap.containsKey(api)) {
                throw new AuraHandledException('Field ' + api + ' not found on Case.');
            }
            if (!fmap.get(api).getDescribe().isUpdateable()) {
                throw new AuraHandledException('No FLS to update ' + api + '.');
            }
        }

        // If the incoming address is blank, clear the compound address and return
        if (String.isBlank(address)) {
            Case clearC = new Case(Id = caseId);
            clearC.put(STREET_API,    null);
            clearC.put(CITY_API,      null);
            clearC.put(STATECODE_API, null);
            clearC.put(POSTAL_API,    null);
            clearC.put(COUNTRY_API,   null);
            update clearC;
            return;
        }

        // Parse the formatted multi-line address created by formatAddress():
        // Line 1: street
        // Line 2: city + state + postal
        // Line 3: country (ignored by parseFormattedAddress)
        AddressParts parts = parseFormattedAddress(address);

        // --- Resolve state input into a valid StateCode value ---
        String resolvedStateCode = null;
        if (!String.isBlank(parts.state)) {
            String raw = parts.state.trim();

            // Build a map of valid StateCode -> Label from org picklist
            Map<String, String> validStates = new Map<String, String>();
            Schema.DescribeFieldResult stateDf = Account.BillingStateCode.getDescribe();
            for (Schema.PicklistEntry pe : stateDf.getPicklistValues()) {
                if (pe.isActive()) {
                    validStates.put(pe.getValue(), pe.getLabel());
                }
            }

            // 1) Direct match by code (e.g., "FL")
            String rawUpper = raw.toUpperCase();
            if (validStates.containsKey(rawUpper)) {
                resolvedStateCode = rawUpper;
            } else {
                // 2) Match by label (e.g., "Florida" -> "FL")
                for (String code : validStates.keySet()) {
                    String label = validStates.get(code);
                    if (label != null && label.equalsIgnoreCase(raw)) {
                        resolvedStateCode = code;
                        break;
                    }
                }
            }
        }

        Case c = new Case(Id = caseId);
        c.put(STREET_API, parts.street);
        c.put(CITY_API,   parts.city);
        c.put(POSTAL_API, parts.postal);

        // For now we assume US; adjust if you need multi-country support
        c.put(COUNTRY_API, 'US');

        // Only set StateCode if we resolved a valid entry
        if (resolvedStateCode != null) {
            c.put(STATECODE_API, resolvedStateCode);
        } else {
            // Clear or leave null to avoid invalid picklist error
            c.put(STATECODE_API, null);
        }

        update c;
    }


    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> searchCodes(String term) {
        List<OptionDTO> out = new List<OptionDTO>();

        // Normalize incoming term
        String q = String.isBlank(term) ? '' : term.trim();
        if (q == '') return out;

        // Security
        Schema.DescribeSObjectResult d = Code__c.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            throw new AuraHandledException('No access to Code__c.');
        }

        // We CANNOT filter by Description__c in SOQL (Long Text Area),
        // so we query a reasonable slice and filter in-memory.
        List<Code__c> rows = [
            SELECT Id, Name, Code__c, Description__c
            FROM Code__c
            LIMIT 1000
        ];

        String qLower = q.toLowerCase();

        // First pass: real matches (by description, code or name)
        for (Code__c r : rows) {
            String descLower = r.Description__c != null ? r.Description__c.toLowerCase() : '';
            String codeLower = r.Code__c != null ? r.Code__c.toLowerCase() : '';
            String nameLower = r.Name != null ? r.Name.toLowerCase() : '';

            // Match if description OR code OR name contains the typed term
            Boolean matches =
                descLower.contains(qLower) ||
                codeLower.contains(qLower) ||
                nameLower.contains(qLower);

            if (!matches) {
                continue;
            }

            String label = '';

            // Show code first (if present)
            if (!String.isBlank(r.Code__c)) {
                label += r.Code__c;
            }

            // Then name
            if (!String.isBlank(r.Name)) {
                label += (label == '' ? '' : ' - ') + r.Name;
            }

            // And description
            if (!String.isBlank(r.Description__c)) {
                label += ' — ' + r.Description__c;
            }

            out.add(new OptionDTO(label, String.valueOf(r.Id)));

            // Do not return more than 50 options to the client
            if (out.size() >= 50) {
                return out;
            }
        }

        // If we got matches, return them
        if (!out.isEmpty()) {
            return out;
        }

        // 🔁 Fallback: no matches -> return a generic list (first 50 rows)
        for (Code__c r : rows) {
            String label = '';

            if (!String.isBlank(r.Code__c)) {
                label += r.Code__c;
            }

            if (!String.isBlank(r.Name)) {
                label += (label == '' ? '' : ' - ') + r.Name;
            }

            if (!String.isBlank(r.Description__c)) {
                label += ' — ' + r.Description__c;
            }

            out.add(new OptionDTO(label, String.valueOf(r.Id)));

            if (out.size() >= 50) {
                break;
            }
        }

        return out;
    }



    // DTO to expose Diagnosis_Code__c + its ICD-9 / ICD-10 codes to LWC
    public class DiagnosisContextDTO {
        @AuraEnabled public Id diagnosisRecordId;

        @AuraEnabled public Id icd9Id;
        @AuraEnabled public String icd9Label;

        @AuraEnabled public Id icd10Id;
        @AuraEnabled public String icd10Label;
    }



    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> searchCodesForDiagnosis(String term, String codeType) {
        List<OptionDTO> out = new List<OptionDTO>();

        // Security
        Schema.DescribeSObjectResult d = Code__c.SObjectType.getDescribe();
        if (!d.isAccessible()) {
            throw new AuraHandledException('No access to Code__c.');
        }

        // Normalize search text
        String q = String.isBlank(term) ? null : term.trim().toLowerCase();

        // Base query: only diagnosis codes, optionally filtered by Type__c
        // IMPORTANT: we do NOT filter by Description__c in SOQL (not filterable).
        String soql =
            'SELECT Id, Name, Code__c, Description__c, Type__c, Diagnosis_Codes__c ' +
            'FROM Code__c ' +
            'WHERE Diagnosis_Codes__c = TRUE';

        if (!String.isBlank(codeType)) {
            soql += ' AND Type__c = :codeType';
        }

        soql += ' ORDER BY Name LIMIT 200';

        List<Code__c> baseRows;
        if (String.isBlank(codeType)) {
            baseRows = Database.query(
                'SELECT Id, Name, Code__c, Description__c, Type__c, Diagnosis_Codes__c ' +
                'FROM Code__c ' +
                'WHERE Diagnosis_Codes__c = TRUE ' +
                'ORDER BY Name LIMIT 200'
            );
        } else {
            baseRows = [
                SELECT Id, Name, Code__c, Description__c, Type__c, Diagnosis_Codes__c
                FROM Code__c
                WHERE Diagnosis_Codes__c = TRUE
                AND Type__c = :codeType
                ORDER BY Name
                LIMIT 200
            ];
        }

        // If user typed something -> filter in memory using Name, Code__c, Description__c
        List<Code__c> pool = baseRows;
        if (q != null && q != '') {
            List<Code__c> filtered = new List<Code__c>();
            for (Code__c r : baseRows) {
                Boolean match = false;

                if (!match && r.Name != null &&
                    r.Name.toLowerCase().contains(q)) {
                    match = true;
                }
                if (!match && r.Code__c != null &&
                    r.Code__c.toLowerCase().contains(q)) {
                    match = true;
                }
                if (!match && r.Description__c != null &&
                    r.Description__c.toLowerCase().contains(q)) {
                    match = true;
                }

                if (match) {
                    filtered.add(r);
                }
            }

            // If there are matches, use them; otherwise, fall back to the base list
            if (!filtered.isEmpty()) {
                pool = filtered;
            }
        }

        // Map to OptionDTO
        for (Code__c r : pool) {
            String label = '';

            if (r.Code__c != null) {
                label += r.Code__c + ' — ';
            }
            label += r.Name;

            if (r.Description__c != null) {
                label += ' — ' + r.Description__c;
            }

            out.add(new OptionDTO(label, String.valueOf(r.Id)));
        }

        return out;
    }

@AuraEnabled
public static void updateCaseDiagnosisCodes(Id caseId, Id codeId) {
    // Basic validation
    if (caseId == null) {
        throw new AuraHandledException('Missing caseId.');
    }

    // Security check: Case
    Schema.DescribeSObjectResult cd = Case.SObjectType.getDescribe();
    if (!cd.isAccessible()) {
        throw new AuraHandledException('No access to Case.');
    }

    // Read Case to obtain the linked Diagnosis_Code__c
    Case c = [
        SELECT Id, trm_Diagnosis_Code__c
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
    ];

    if (c.trm_Diagnosis_Code__c == null) {
        throw new AuraHandledException('Case does not have a Diagnosis Code record (trm_Diagnosis_Code__c).');
    }

    // Security check: Diagnosis_Code__c
    Schema.DescribeSObjectResult dDiag = Diagnosis_Code__c.SObjectType.getDescribe();
    if (!dDiag.isAccessible()) {
        throw new AuraHandledException('No access to Diagnosis_Code__c.');
    }

    Map<String, Schema.SObjectField> diagFields = dDiag.fields.getMap();
    final String ICD9_API  = 'ICD9__c';
    final String ICD10_API = 'ICD10__c';

    for (String api : new List<String>{ ICD9_API, ICD10_API }) {
        if (!diagFields.containsKey(api)) {
            throw new AuraHandledException('Field ' + api + ' not found on Diagnosis_Code__c.');
        }
        if (!diagFields.get(api).getDescribe().isUpdateable()) {
            throw new AuraHandledException('No FLS to update ' + api + '.');
        }
    }

    // If codeId is null, you can choose behavior:
    // here we clear BOTH ICD-9 and ICD-10
    if (codeId == null) {
        Diagnosis_Code__c clearDiag = new Diagnosis_Code__c(
            Id     = c.trm_Diagnosis_Code__c,
            ICD9__c  = null,
            ICD10__c = null
        );
        update clearDiag;
        return;
    }

    // Security check: Code__c
    Schema.DescribeSObjectResult dCode = Code__c.SObjectType.getDescribe();
    if (!dCode.isAccessible()) {
        throw new AuraHandledException('No access to Code__c.');
    }

    // Load the selected Code__c to inspect Type__c and Diagnosis_Codes__c
    Code__c codeRec = [
        SELECT Id, Type__c, Diagnosis_Codes__c
        FROM Code__c
        WHERE Id = :codeId
        LIMIT 1
    ];

    if (!codeRec.Diagnosis_Codes__c) {
        throw new AuraHandledException('Selected Code is not marked as a Diagnosis Code.');
    }

    Diagnosis_Code__c diagToUpdate = new Diagnosis_Code__c(
        Id = c.trm_Diagnosis_Code__c
    );

    // Decide which field to update based on Type__c
    if (codeRec.Type__c == 'ICD 9') {
        diagToUpdate.ICD9__c = codeId;
    } else if (codeRec.Type__c == 'ICD 10') {
        diagToUpdate.ICD10__c = codeId;
    } else {
        throw new AuraHandledException('Selected Code is not of type ICD 9 or ICD 10.');
    }

    update diagToUpdate;
}

@AuraEnabled(cacheable=true)
public static Map<String, Object> fetchDiagnosisContextForCase(Id caseId) {
    // Default response
    Map<String, Object> out = new Map<String, Object>{
        'hasDiagnosis' => false,
        'diagnosisId'  => null,
        'icd9Id'       => null,
        'icd9Label'    => null,
        'icd10Id'      => null,
        'icd10Label'   => null
    };

    if (caseId == null) {
        return out;
    }

    // Check Case access
    Schema.DescribeSObjectResult cd = Case.SObjectType.getDescribe();
    if (!cd.isAccessible()) {
        return out;
    }

    // Read Case + Diagnosis_Code__c + Code__c for ICD-9 / ICD-10
    Case c = [
        SELECT Id,
               trm_Diagnosis_Code__c,
               trm_Diagnosis_Code__r.ICD9__c,
               trm_Diagnosis_Code__r.ICD9__r.Id,
               trm_Diagnosis_Code__r.ICD9__r.Code__c,
               trm_Diagnosis_Code__r.ICD9__r.Name,
               trm_Diagnosis_Code__r.ICD9__r.Description__c,
               trm_Diagnosis_Code__r.ICD10__c,
               trm_Diagnosis_Code__r.ICD10__r.Id,
               trm_Diagnosis_Code__r.ICD10__r.Code__c,
               trm_Diagnosis_Code__r.ICD10__r.Name,
               trm_Diagnosis_Code__r.ICD10__r.Description__c
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
    ];

    if (c.trm_Diagnosis_Code__c == null) {
        return out;
    }

    out.put('hasDiagnosis', true);
    out.put('diagnosisId', c.trm_Diagnosis_Code__c);

    // Helper for label formatting (same “Code — Name — Description” style)
    // ICD-9
    if (c.trm_Diagnosis_Code__r.ICD9__c != null &&
        c.trm_Diagnosis_Code__r.ICD9__r != null) {

        Code__c icd9 = c.trm_Diagnosis_Code__r.ICD9__r;

        String lbl9 = '';
        if (icd9.Code__c != null) {
            lbl9 += icd9.Code__c + ' — ';
        }
        lbl9 += icd9.Name;
        if (icd9.Description__c != null) {
            lbl9 += ' — ' + icd9.Description__c;
        }

        out.put('icd9Id', icd9.Id);
        out.put('icd9Label', lbl9);
    }

    // ICD-10
    if (c.trm_Diagnosis_Code__r.ICD10__c != null &&
        c.trm_Diagnosis_Code__r.ICD10__r != null) {

        Code__c icd10 = c.trm_Diagnosis_Code__r.ICD10__r;

        String lbl10 = '';
        if (icd10.Code__c != null) {
            lbl10 += icd10.Code__c + ' — ';
        }
        lbl10 += icd10.Name;
        if (icd10.Description__c != null) {
            lbl10 += ' — ' + icd10.Description__c;
        }

        out.put('icd10Id', icd10.Id);
        out.put('icd10Label', lbl10);
    }

    return out;
}

@AuraEnabled(cacheable=true)
public static List<OptionDTO> searchCodesByType(String term, String codeType) {
    List<OptionDTO> out = new List<OptionDTO>();

    // Normalize input
    String q = String.isBlank(term) ? null : term.trim().toLowerCase();
    String type = String.isBlank(codeType) ? null : codeType.trim();

    // Security
    Schema.DescribeSObjectResult d = Code__c.SObjectType.getDescribe();
    if (!d.isAccessible()) {
        throw new AuraHandledException('No access to Code__c.');
    }

    // Build base SOQL (only filterable fields)
    String soql = 
        'SELECT Id, Name, Code__c, Description__c, Type__c, Diagnosis_Codes__c ' +
        'FROM Code__c ' +
        'WHERE Diagnosis_Codes__c = TRUE';

    if (type != null) {
        soql += ' AND Type__c = :type';
    }

    soql += ' ORDER BY Name LIMIT 200';

    List<Code__c> baseRows = (List<Code__c>)Database.query(soql);

    List<Code__c> pool = baseRows;

    // In-memory filter by Name / Code__c / Description__c
    if (q != null && q != '') {
        List<Code__c> filtered = new List<Code__c>();
        for (Code__c r : baseRows) {
            Boolean match = false;

            if (!match && r.Name != null &&
                r.Name.toLowerCase().contains(q)) {
                match = true;
            }
            if (!match && r.Code__c != null &&
                r.Code__c.toLowerCase().contains(q)) {
                match = true;
            }
            if (!match && r.Description__c != null &&
                r.Description__c.toLowerCase().contains(q)) {
                match = true;
            }

            if (match) {
                filtered.add(r);
            }
        }
        if (!filtered.isEmpty()) {
            pool = filtered;
        }
    }

    // Map to OptionDTO
    for (Code__c r : pool) {
        String label = '';
        if (r.Code__c != null) {
            label += r.Code__c + ' — ';
        }
        label += r.Name;
        if (r.Description__c != null) {
            label += ' — ' + r.Description__c;
        }
        out.add(new OptionDTO(label, String.valueOf(r.Id)));
    }

    return out;
}

@AuraEnabled(cacheable=true)
public static List<CodeOptionDTO> searchIcdCodes(String term, String icdType) {
    // Normalizamos parámetros
    String q = String.isBlank(term) ? '' : term.trim();
    String typeFilter = String.isBlank(icdType) ? 'ICD 9' : icdType.trim();

    // IMPORTANTE: aquí usamos exactamente los valores del picklist
    // Type__c = 'ICD 9' o 'ICD 10'

    String likeTerm = '%' + String.escapeSingleQuotes(q) + '%';

    // 1) Intento con filtro por texto
    List<Code__c> rows = [
        SELECT Id, Code__c, Name, Type__c
        FROM Code__c
        WHERE Diagnosis_Codes__c = true
          AND Type__c = :typeFilter
          AND (Code__c LIKE :likeTerm OR Name LIKE :likeTerm)
        ORDER BY Code__c
        LIMIT 50
    ];

    // 2) Si no hay matches, devolvemos una lista por defecto del mismo tipo
    if (rows.isEmpty()) {
        rows = [
            SELECT Id, Code__c, Name, Type__c
            FROM Code__c
            WHERE Diagnosis_Codes__c = true
              AND Type__c = :typeFilter
            ORDER BY Code__c
            LIMIT 50
        ];
    }

    // 3) Mapear a DTO para el LWC
    List<CodeOptionDTO> out = new List<CodeOptionDTO>();
    for (Code__c c : rows) {
        CodeOptionDTO dto = new CodeOptionDTO();
        dto.value = c.Id;
        dto.label =
            (c.Code__c != null ? c.Code__c : '') +
            (c.Name != null ? ' - ' + c.Name : '');
        out.add(dto);
    }
    return out;
}



// DTO simple para opciones de combobox
public class CodeOptionDTO {
    @AuraEnabled public Id value;
    @AuraEnabled public String label;
}

@AuraEnabled
public static void updateDiagnosisCodes(Id caseId, Id icd9Id, Id icd10Id) {
    if (caseId == null) {
        throw new AuraHandledException('Missing caseId.');
    }

    // 1) Traer el Case y Diagnosis_Code__c (similar a lo que ya tienes)
    Case c = [
        SELECT Id, CaseNumber, trm_Diagnosis_Code__c
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
    ];

    Diagnosis_Code__c diag;

    if (c.trm_Diagnosis_Code__c != null) {
        diag = [
            SELECT Id, ICD9__c, ICD10__c, Allocation__c
            FROM Diagnosis_Code__c
            WHERE Id = :c.trm_Diagnosis_Code__c
            LIMIT 1
        ];
        diag.ICD9__c  = icd9Id;
        diag.ICD10__c = icd10Id;
        update diag;
    } else {
        diag = new Diagnosis_Code__c(
            Allocation__c = c.Id,
            ICD9__c       = icd9Id,
            ICD10__c      = icd10Id,
            Name          = 'Diagnosis - ' + c.CaseNumber
        );
        insert diag;

        c.trm_Diagnosis_Code__c = diag.Id;
        update c;
    }

    // 2) Volver a leer el Diagnosis_Code__c con los Code__c reales
    Diagnosis_Code__c diagWithCodes = [
        SELECT Id,
               Allocation__c,
               ICD9__r.Code__c,
               ICD10__r.Code__c
        FROM Diagnosis_Code__c
        WHERE Id = :diag.Id
        LIMIT 1
    ];

    // 3) Armar el texto ANSI109; 1001F (solo códigos no nulos)
    List<String> codes = new List<String>();
    if (diagWithCodes.ICD9__r != null && !String.isBlank(diagWithCodes.ICD9__r.Code__c)) {
        codes.add(diagWithCodes.ICD9__r.Code__c);
    }
    if (diagWithCodes.ICD10__r != null && !String.isBlank(diagWithCodes.ICD10__r.Code__c)) {
        codes.add(diagWithCodes.ICD10__r.Code__c);
    }

    String allCodes = String.join(codes, '; ');

    // 4) Guardar el texto final en el Case
    Case caseToUpdate = new Case(
        Id = diagWithCodes.Allocation__c,
        trm_All_Diagnosis_Codes__c = allCodes
    );
    update caseToUpdate;
}


public class DynamicInputDTO {
    @AuraEnabled public String key;
    @AuraEnabled public String fieldApi;
    @AuraEnabled public String value;
}

@AuraEnabled
public static void persistDynamicInputs(Id caseId, List<Map<String, Object>> inputs) {
    System.debug('🔥 persistDynamicInputs CALLED');
    System.debug('caseId = ' + caseId);
    System.debug('inputs size = ' + (inputs == null ? 0 : inputs.size()));
    System.debug('raw inputs = ' + inputs);

    if (caseId == null) {
        throw new AuraHandledException('Missing caseId.');
    }
    if (inputs == null || inputs.isEmpty()) {
        return;
    }

    Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
    if (!d.isAccessible()) {
        throw new AuraHandledException('No access to Case.');
    }

    Map<String, Schema.SObjectField> fmap = d.fields.getMap();
    Case c = new Case(Id = caseId);

    for (Map<String, Object> m : inputs) {
        String key      = (String) m.get('key');
        String fieldApi = (String) m.get('fieldApi');
        String value    = (String) m.get('value');

        System.debug('➡️ Processing input: key=' + key + ', fieldApi=' + fieldApi + ', value=' + value);

        if (String.isBlank(fieldApi)) {
            continue;
        }
        if (!fmap.containsKey(fieldApi)) {
            System.debug('⚠️ Field not found on Case: ' + fieldApi);
            continue;
        }
        if (!fmap.get(fieldApi).getDescribe().isUpdateable()) {
            System.debug('⚠️ No FLS to update field: ' + fieldApi);
            continue;
        }

        c.put(fieldApi, value);
    }

    System.debug('💾 Updating Case with dynamic inputs...');
    update c;
    System.debug('✅ Case updated successfully in persistDynamicInputs');

    // (Opcional) verificación post-update
    Case c2 = [
        SELECT trm_Documentation_Request__c
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
    ];
    System.debug('🔎 After update DB value = ' + c2.trm_Documentation_Request__c);
}


@AuraEnabled
public static void setCaseLRDates(Id caseId, Date dateIssued, Date datePriorIssued) {
    if (caseId == null) {
        throw new AuraHandledException('Missing Case Id');
    }

    // Opcional: seguridad básica de acceso al objeto Case
    Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
    if (!d.isAccessible()) {
        throw new AuraHandledException('No access to Case.');
    }

    Case c = new Case(
        Id = caseId,
        LR_Date_Issued__c = dateIssued,
        LR_Prior_Dispute_Issued__c = datePriorIssued
    );
    update c;
}

    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> fetchAccountAddresses(Id caseId) {
        // Build dropdown options using:
        // - Billing  : Case.Payee_Address__r.Address__c   (compound)
        // - Mailing  : Account Billing Address
        // - Main/Physical : Account Shipping Address
        List<OptionDTO> out = new List<OptionDTO>();
        if (caseId == null) return out;

        // Query only what's needed; DO NOT try to read Street__c/City__c on Address__c
        Case c = [
            SELECT Id,
                AccountId,
                Payee_Address__r.Address__c // <- compound address case
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        if (c.Payee_Address__r != null && c.Payee_Address__r.Address__c != null) {
            System.Address a = c.Payee_Address__r.Address__c;
            String billingVal = formatAddress(a.street, a.city, a.state, a.postalCode, a.country);
            if (!String.isBlank(billingVal)) {
                // Label = una línea; Value = multilínea
                out.add(new OptionDTO('Billing - ' + billingVal.replace('\n', ' '), billingVal));
            }
        }

        // ---- Mailing (Account Billing...) & Main/Physical (Account Shipping...) ----
        if (c.AccountId != null) {
            Account acc = [
                SELECT Id, Name,
                    BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                    ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
                FROM Account
                WHERE Id = :c.AccountId
                LIMIT 1
            ];

            // Mailing = Account Billing
            String mailing = formatAddress(
                acc.BillingStreet, acc.BillingCity, acc.BillingState, acc.BillingPostalCode, acc.BillingCountry
            );
            if (!String.isBlank(mailing)) {
                out.add(new OptionDTO('Mailing - ' + mailing.replace('\n', ' '), mailing));
            }

            // Main/Physical = Account Shipping
            String mainPhysical = formatAddress(
                acc.ShippingStreet, acc.ShippingCity, acc.ShippingState, acc.ShippingPostalCode, acc.ShippingCountry
            );
            if (!String.isBlank(mainPhysical)) {
                out.add(new OptionDTO('Main/Physical - ' + mainPhysical.replace('\n', ' '), mainPhysical));
            }
        }


        return out;
    }



}