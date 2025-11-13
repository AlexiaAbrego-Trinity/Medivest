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

        System.debug('current user' + currentUser.FirstName);
        System.debug('current user' + currentUser.Extension);
        System.debug('current user' + currentUser.LastName);
        System.debug('current user' + currentUser.Title);

        // Parse user information
        String firstName = (currentUser.FirstName != null) ? currentUser.FirstName : parseFirstName(currentUser.Name);
        String lastName = (currentUser.LastName != null) ? currentUser.LastName : parseLastName(currentUser.Name);
        String extension = currentUser.Extension;//parseExtension(currentUser.Phone);
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

    @AuraEnabled
    public static void setCasePeriodDates(Id caseId, Date dateStart, Date dateEnd) {
        // --- Local messages and field API names for easy maintenance ---
        final Map<String, String> ERR = new Map<String, String>{
            'MISSING_ID'     => 'Missing caseId.',
            'NO_ACCESS'      => 'No access to Case.',
            'FIELDS_MISSING' => 'Date fields not found on Case.',
            'NO_FLS'         => 'No FLS to edit date fields.'
        };
        final Set<String> DATE_FIELDS = new Set<String>{
            'trm_Date_Period_Start__c',
            'trm_Date_Period_End__c'
        };

        // --- (Optional) Business rule: end date must not be before start date ---
        if (dateStart != null && dateEnd != null && dateEnd < dateStart) {
            throw new AuraHandledException('Date Period 2 cannot be before Date Period 1.');
        }

        // --- Basic validation: id, object access, fields exist, FLS updatable ---
        if (caseId == null) throw new AuraHandledException(ERR.get('MISSING_ID'));

        Schema.DescribeSObjectResult caseDescribe = Case.SObjectType.getDescribe();
        if (!caseDescribe.isAccessible()) throw new AuraHandledException(ERR.get('NO_ACCESS'));

        Map<String, Schema.SObjectField> fmap = caseDescribe.fields.getMap();
        for (String api : DATE_FIELDS) {
            if (!fmap.containsKey(api)) throw new AuraHandledException(ERR.get('FIELDS_MISSING'));
            if (!fmap.get(api).getDescribe().isUpdateable()) throw new AuraHandledException(ERR.get('NO_FLS'));
        }

        // --- Single DML update: null values will clear the fields, non-null will set them ---
        Case c = new Case(Id = caseId);
        c.put('trm_Date_Period_Start__c', dateStart);
        c.put('trm_Date_Period_End__c',   dateEnd);
        update c;
    }

    @AuraEnabled
    public static void clearCasePeriodDates(Id caseId) {
        // --- Local messages and field API names for easy maintenance ---
        final Map<String, String> ERR = new Map<String, String>{
            'MISSING_ID'     => 'Missing caseId.',
            'NO_ACCESS'      => 'No access to Case.',
            'FIELDS_MISSING' => 'Date fields not found on Case.',
            'NO_FLS'         => 'No FLS to edit date fields.'
        };
        final Set<String> DATE_FIELDS = new Set<String>{
            'trm_Date_Period_Start__c',
            'trm_Date_Period_End__c'
        };

        // --- Tolerant validation: return quietly if any prerequisite fails ---
        if (caseId == null) return;

        Schema.DescribeSObjectResult caseDescribe = Case.SObjectType.getDescribe();
        if (!caseDescribe.isAccessible()) return;

        Map<String, Schema.SObjectField> fmap = caseDescribe.fields.getMap();
        for (String api : DATE_FIELDS) {
            if (!fmap.containsKey(api)) return;
            if (!fmap.get(api).getDescribe().isUpdateable()) return;
        }

        // --- Single DML update wrapped in try/catch to avoid breaking the LWC flow ---
        try {
            Case c = new Case(Id = caseId);
            c.put('trm_Date_Period_Start__c', null);
            c.put('trm_Date_Period_End__c',   null);
            update c;
        } catch (Exception ex) {
            // Intentionally silenced to not interrupt the UI flow
            // If desired, log a warning: System.debug(LoggingLevel.WARN, ex.getMessage());
        }
    }

    @AuraEnabled
    public static void setCaseAnnuity(Id caseId, Decimal annuity) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');
        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (!fmap.containsKey('trm_Annuity__c'))
            throw new AuraHandledException('Field trm_Annuity__c not found.');
        if (!fmap.get('trm_Annuity__c').getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update trm_Annuity__c.');

        update new Case(
            Id = caseId,
            trm_Annuity__c = annuity
        );
    }
    
    /*@AuraEnabled
    public static Id mapClosestActiveExhaustionToCase(Id caseId) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');
        // Asegura acceso y FLS
        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');
        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (!fmap.containsKey('trm_Exhaustion__c'))
            throw new AuraHandledException('Field trm_Exhaustion__c not found on Case.');
        if (!fmap.get('trm_Exhaustion__c').getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update trm_Exhaustion__c.');

        // 1) Obtener Account.Name del Case
        Case c = [
            SELECT Id, Account.Name
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];
        if (c.Account == null || String.isBlank(c.Account.Name)) return null;

        // 2) Buscar Exhaustion activa y futura más cercana
        List<Exhaustion__c> ex = [
            SELECT Id, ExhaustionDate__c, Active__c
            FROM Exhaustion__c
            WHERE Helper_Member_Name__c = :c.Account.Name
            AND Active__c = true
            AND ExhaustionDate__c >= :Date.today()
            ORDER BY ExhaustionDate__c ASC
            LIMIT 1
        ];

        Id picked = ex.isEmpty() ? null : ex[0].Id;

        // 3) Mapear en Case.trm_Exhaustion__c (puede quedar null si no hay match)
        update new Case(
            Id = caseId,
            trm_Exhaustion__c = picked
        );

        return picked;
    }*/

    @AuraEnabled
    public static void setCaseFundingChange(Id caseId, String fundingChange) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');
        if (String.isBlank(fundingChange)) {
            return;
        }

        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (!fmap.containsKey('trm_Funding_Change__c'))
            throw new AuraHandledException('Field trm_Funding_Change__c not found.');
        if (!fmap.get('trm_Funding_Change__c').getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update trm_Funding_Change__c.');

        update new Case(
            Id = caseId,
            trm_Funding_Change__c = fundingChange
        );
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> fetchPayeeAddresses(Id caseId) {
        // Build dropdown options using:
        // - Billing  : Case.Payee_Address__r.Address__c   (compound)
        // - Mailing  : Account Billing Address
        // - Main/Physical : Account Shipping Address
        List<OptionDTO> out = new List<OptionDTO>();
        if (caseId == null) return out;

        // Query only what's needed; DO NOT try to read Street__c/City__c on Address__c
        Case c = [
            SELECT Id,
                Payee_Name__c,
                Payee_Address__r.Address__c        // compound Address field
            FROM Case
            WHERE Id = :caseId
            LIMIT 1
        ];

        // ---- Billing (Case-level compound address) ----
        if (c.Payee_Address__r != null && c.Payee_Address__r.Address__c != null) {
            // Treat compound as System.Address in Apex
            System.Address a = c.Payee_Address__r.Address__c;
            String billingVal = formatAddress(a.street, a.city, a.state, a.postalCode, a.country);
            if (!String.isBlank(billingVal)) {
                // Label shows one-line preview, value keeps the multi-line address
                out.add(new OptionDTO('Billing - ' + billingVal.replace('\n', ' '), billingVal));
            }
        }

        // ---- Mailing (Account Billing...) & Main/Physical (Account Shipping...) ----
        if (c.Payee_Name__c != null) {
            Account acc = [
                SELECT Id, Name,
                    BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry,
                    ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry
                FROM Account
                WHERE Id = :c.Payee_Name__c
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


    // Helper kept as-is
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


    // ---- Keep this helper class the same ----
    private class AddressParts {
        String street;
        String city;
        String state;
        String postal;
    }

    /**
     * Parses the formatted address we create with formatAddress():
     *   Line 1: <street>
     *   Line 2: <city>[,] <state> <postal>
     *   Line 3: <country>   (ignored here)
     *
     * It is defensive and handles: "City ST 12345", "City, ST 12345", "City, State 12345", etc.
     */
    private static AddressParts parseFormattedAddress(String formatted) {
        AddressParts ap = new AddressParts();
        if (String.isBlank(formatted)) return ap;

        // Split by newline added by formatAddress
        List<String> lines = formatted.split('\\n');

        // Line 1 → Street
        if (!lines.isEmpty()) {
            String l1 = lines[0];
            ap.street = (l1 != null) ? l1.trim() : null;
        }

        // Line 2 → City, State, Postal (several tolerant patterns)
        if (lines.size() >= 2) {
            String line2Raw = lines[1];
            String line2 = (line2Raw != null) ? line2Raw.trim() : '';

            // Pattern 1: "City, ST 12345"  (comma optional), state = 2+ letters
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
                // Pattern 2: "City With Spaces ST 12345" (no comma)
                List<String> tokens = (line2 == null) ? new List<String>() : line2.split('\\s+');
                if (tokens.size() >= 3) {
                    ap.state  = tokens[tokens.size()-2];
                    ap.postal = tokens[tokens.size()-1];
                    List<String> cityParts = new List<String>();
                    for (Integer i = 0; i < tokens.size()-2; i++) cityParts.add(tokens[i]);
                    ap.city = String.join(cityParts, ' ');
                } else if (line2 != null && line2.contains(',')) {
                    // Pattern 3: "City, Rest" → try comma split
                    List<String> parts = line2.split(',', 2);
                    ap.city = (parts.size() > 0 && parts[0] != null) ? parts[0].trim() : null;

                    String right = (parts.size() > 1) ? parts[1] : null;
                    List<String> rightTokens = (right == null) ? new List<String>() : right.trim().split('\\s+');
                    if (rightTokens.size() >= 2) {
                        ap.state  = rightTokens[0];
                        ap.postal = rightTokens[1];
                    }
                } else {
                    // Fallback: treat all as city if we cannot infer state/postal
                    ap.city = line2;
                }
            }
        }
        // Country (line 3) intentionally ignored here
        return ap;
    }

    /**
     * Persist the selected address into 4 Case text fields:
     *  - trm_Address_Street__c
     *  - trm_Address_City__c
     *  - trm_Address_State__c
     *  - trm_Address_PostalCode__c
     *
     * The input "address" is the same multi-line string used in the picklist.
     */
    @AuraEnabled
    public static void setCaseAddress(Id caseId, String address) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');
        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();

        // Target field API names
        final String STREET_API  = 'trm_Address_Street__c';
        final String CITY_API    = 'trm_Address_City__c';
        final String STATE_API   = 'trm_Address_State__c';
        final String POSTAL_API  = 'trm_Address_PostalCode__c';

        // Ensure fields exist and are updateable
        for (String api : new List<String>{STREET_API, CITY_API, STATE_API, POSTAL_API}) {
            if (!fmap.containsKey(api)) {
                throw new AuraHandledException('Field ' + api + ' not found on Case.');
            }
            if (!fmap.get(api).getDescribe().isUpdateable()) {
                throw new AuraHandledException('No FLS to update ' + api + '.');
            }
        }

        // If the incoming address is blank, clear all 4 fields and return
        if (String.isBlank(address)) {
            Case clearC = new Case(
                Id = caseId,
                trm_Address_Street__c    = null,
                trm_Address_City__c      = null,
                trm_Address_State__c     = null,
                trm_Address_PostalCode__c= null
            );
            update clearC;
            return;
        }

        // Parse the multi-line string into parts
        AddressParts parts = parseFormattedAddress(address);

        // Single DML update
        Case c = new Case(Id = caseId);
        c.put(STREET_API, parts.street);
        c.put(CITY_API,   parts.city);
        c.put(STATE_API,  parts.state);
        c.put(POSTAL_API, parts.postal);
        update c;
    }



    private static String tryGetString(SObject s, String api) {
        // Safely returns a field value as string if the field exists, else null
        Schema.SObjectType t = s.getSObjectType();
        Map<String, Schema.SObjectField> fmap = t.getDescribe().fields.getMap();
        if (!fmap.containsKey(api)) return null;
        Object val = s.get(api);
        return (val == null) ? null : String.valueOf(val);
    }

    @AuraEnabled
    public static void setCaseInsertInformation(Id caseId, String insertInformation) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');

        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');

        
        final String INFO_API = 'trm_Insert_Information__c';

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (!fmap.containsKey(INFO_API))
            throw new AuraHandledException('Field ' + INFO_API + ' not found on Case.');
        if (!fmap.get(INFO_API).getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update ' + INFO_API + '.');

        // if blank saves null
        String valueToSave = String.isBlank(insertInformation) ? null : insertInformation;

        Case c = new Case(Id = caseId);
        c.put(INFO_API, valueToSave);
        update c;
    }

    @AuraEnabled(cacheable=true)
    public static List<OptionDTO> searchCodes(String term) {
        List<OptionDTO> out = new List<OptionDTO>();
        String q = String.isBlank(term) ? '' : term.trim();
        if (q == '') return out;

        // Seguridad
        Schema.DescribeSObjectResult d = Code__c.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Code__c.');

        String likeTerm = '%' + String.escapeSingleQuotes(q) + '%';

        // 1) Buscar por Name/Code__c (SOQL permitido)
        List<Code__c> rows = [
            SELECT Id, Name, Code__c, Description__c
            FROM Code__c
            WHERE Name LIKE :likeTerm
            OR Code__c LIKE :likeTerm
            ORDER BY Name
            LIMIT 50
        ];

        // 2) (Opcional) Filtrado extra por Descripción EN MEMORIA
        List<Code__c> filtered = new List<Code__c>();
        for (Code__c r : rows) {
            if (String.isBlank(q)) { filtered.add(r); continue; }
            Boolean matchesDesc = (r.Description__c != null && r.Description__c.toLowerCase().contains(q.toLowerCase()));
            // Si ya matcheó por Name/Code__c lo tenemos en rows; no necesitamos forzar desc,
            // pero si quieres priorizar, puedes dejarlo así:
            filtered.add(r);
            // Si quisieras requerir que también matchee descripción, cambia la lógica.
        }

        for (Code__c r : filtered) {
            String label = r.Name;
            if (r.Code__c != null) label += ' — ' + r.Code__c;
            if (r.Description__c != null) label += ' — ' + r.Description__c;
            out.add(new OptionDTO(label, String.valueOf(r.Id)));
        }
        return out;
    }

    /*@AuraEnabled
    public static void setCaseDiagnosisCode(Id caseId, Id codeId) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');
        // Access
        Schema.DescribeSObjectResult cd = Case.SObjectType.getDescribe();
        if (!cd.isAccessible()) throw new AuraHandledException('No access to Case.');
        Map<String, Schema.SObjectField> fmap = cd.fields.getMap();
        String fieldApi = 'trm_Injured_Diagnosis__c'; 
        if (!fmap.containsKey(fieldApi))
            throw new AuraHandledException('Field ' + fieldApi + ' not found on Case.');
        if (!fmap.get(fieldApi).getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update ' + fieldApi + '.');

        // (Opcional) calidates code exists
        if (codeId != null) {
            Schema.DescribeSObjectResult dd = Code__c.SObjectType.getDescribe();
            if (!dd.isAccessible()) throw new AuraHandledException('No access to Code__c.');
            Integer cnt = [SELECT COUNT() FROM Code__c WHERE Id = :codeId];
            if (cnt == 0) throw new AuraHandledException('Invalid Diagnosis Code Id.');
        }

        update new Case(Id = caseId, trm_Diagnosis_Code__c = codeId);
    }*/

    @AuraEnabled
    public static void setCaseInjuredDiagnosis(Id caseId, Id codeId) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');

        // FLS y existencia del campo en Case
        Schema.DescribeSObjectResult cd = Case.SObjectType.getDescribe();
        if (!cd.isAccessible()) throw new AuraHandledException('No access to Case.');
        Map<String, Schema.SObjectField> fmap = cd.fields.getMap();
        String fieldApi = 'trm_Injured_Diagnosis__c';
        if (!fmap.containsKey(fieldApi))
            throw new AuraHandledException('Field ' + fieldApi + ' not found on Case.');
        if (!fmap.get(fieldApi).getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update ' + fieldApi + '.');

        String textToSave = null;

        // Si vino un código, lee su descripción; si está vacía, usa Name como respaldo
        if (codeId != null) {
            // Acceso a Code__c
            Schema.DescribeSObjectResult dd = Code__c.SObjectType.getDescribe();
            if (!dd.isAccessible()) throw new AuraHandledException('No access to Code__c.');

            Code__c c = [
                SELECT Id, Name, Code__c, Description__c
                FROM Code__c
                WHERE Id = :codeId
                LIMIT 1
            ];
            // SOLO texto: preferimos la descripción
            textToSave = String.isBlank(c.Description__c) ? c.Name : c.Description__c;
        }

        // Guarda únicamente el texto en Case.trm_Injured_Diagnosis__c
        update new Case(
            Id = caseId,
            trm_Injured_Diagnosis__c = textToSave
        );
    }

    @AuraEnabled
    public static void setCaseWithdrawalExtras(Id caseId, String carrierOrInsurance, String allocationCompany) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');

        // --- Security & FLS checks on Case ---
        Schema.DescribeSObjectResult cd = Case.SObjectType.getDescribe();
        if (!cd.isAccessible()) throw new AuraHandledException('No access to Case.');
        Map<String, Schema.SObjectField> fmap = cd.fields.getMap();

        // Target Case fields (change API names here if your org uses different ones)
        final String CARRIER_API   = 'trm_Carrier_Or_insurance__c';
        final String COMPANY_API   = 'trm_Allocation_Company__c';

        // Ensure fields exist and are updateable
        for (String api : new List<String>{ CARRIER_API, COMPANY_API }) {
            if (!fmap.containsKey(api)) {
                throw new AuraHandledException('Field ' + api + ' not found on Case.');
            }
            if (!fmap.get(api).getDescribe().isUpdateable()) {
                throw new AuraHandledException('No FLS to update ' + api + '.');
            }
        }

        // Normalize blanks to null to allow clearing values
        String vCarrier = String.isBlank(carrierOrInsurance) ? null : carrierOrInsurance;
        String vCompany = String.isBlank(allocationCompany)  ? null : allocationCompany;

        // Single DML update
        Case c = new Case(Id = caseId);
        c.put(CARRIER_API, vCarrier);
        c.put(COMPANY_API, vCompany);
        update c;
    }

    @AuraEnabled
    public static void setSpecifyReason(Id caseId, String insertInformation) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');

        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');

        
        final String INFO_API = 'trm_Specify_Reason__c';

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (!fmap.containsKey(INFO_API))
            throw new AuraHandledException('Field ' + INFO_API + ' not found on Case.');
        if (!fmap.get(INFO_API).getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update ' + INFO_API + '.');

        // if blank saves null
        String valueToSave = String.isBlank(insertInformation) ? null : insertInformation;

        Case c = new Case(Id = caseId);
        c.put(INFO_API, valueToSave);
        update c;
    }
    
    @AuraEnabled
    public static void setDocumentationRequest(Id caseId, String insertInformation) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');

        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');

        
        final String INFO_API = 'trm_Documentation_Requested__c';

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (!fmap.containsKey(INFO_API))
            throw new AuraHandledException('Field ' + INFO_API + ' not found on Case.');
        if (!fmap.get(INFO_API).getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update ' + INFO_API + '.');

        // if blank saves null
        String valueToSave = String.isBlank(insertInformation) ? null : insertInformation;

        Case c = new Case(Id = caseId);
        c.put(INFO_API, valueToSave);
        update c;
    }

    @AuraEnabled
    public static void setProviderAttention(Id caseId, String providerAttention) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');

        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) throw new AuraHandledException('No access to Case.');

        
        final String INFO_API = 'trm_Provider_Attention__c';

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (!fmap.containsKey(INFO_API))
            throw new AuraHandledException('Field ' + INFO_API + ' not found on Case.');
        if (!fmap.get(INFO_API).getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update ' + INFO_API + '.');

        // if blank saves null
        String valueToSave = String.isBlank(providerAttention) ? null : providerAttention;

        Case c = new Case(Id = caseId);
        c.put(INFO_API, valueToSave);
        update c;
    }

    @AuraEnabled
    public static void setCaseNextAnnuityDate(Id caseId, Date insertDate) {
        if (caseId == null) 
            throw new AuraHandledException('Missing caseId.');

        Schema.DescribeSObjectResult d = Case.SObjectType.getDescribe();
        if (!d.isAccessible()) 
            throw new AuraHandledException('No access to Case.');

        // ⚙️ Cambia este nombre al API name del campo Date real
        final String INFO_API = 'trm_Next_Annuity__c';

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();
        if (!fmap.containsKey(INFO_API))
            throw new AuraHandledException('Field ' + INFO_API + ' not found on Case.');
        if (!fmap.get(INFO_API).getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update ' + INFO_API + '.');

        // Si el valor es nulo, guarda null, si no, guarda el Date recibido
        Date valueToSave = insertDate;

        Case c = new Case(Id = caseId);
        c.put(INFO_API, valueToSave);
        update c;
    }

    // ===== Exhaustion picklist DTO =====
    public class ExhaustionPicklistDTO {
        @AuraEnabled public List<OptionDTO> options;
        @AuraEnabled public Id recommendedId;
        public ExhaustionPicklistDTO() {
            options = new List<OptionDTO>();
        }
    }

/**
 * Returns ONLY ACTIVE Exhaustion__c records for the Case's Custodial_Account__c
 * as picklist options (label shows Replenishment/annuity and Exhaustion).
 *
 * recommendedId:
 *   - The ACTIVE exhaustion with the nearest Replenishment_Date__c to today.
 */
@AuraEnabled(cacheable=true)
public static ExhaustionPicklistDTO fetchExhaustionsForCase(Id caseId) {
    ExhaustionPicklistDTO out = new ExhaustionPicklistDTO();
    if (caseId == null) return out;

    // Security: ensure the running user has access to Case
    Schema.DescribeSObjectResult cd = Case.SObjectType.getDescribe();
    if (!cd.isAccessible()) return out;

    // Read Member Account (Custodial_Account__c) from Case
    Case c = [
        SELECT Id, Custodial_Account__c
        FROM Case
        WHERE Id = :caseId
        LIMIT 1
    ];

    if (c.Custodial_Account__c == null) {
        // No Member Account linked → nothing to return
        return out;
    }

    Date today = Date.today();

    // Fetch ONLY ACTIVE Exhaustion__c rows.
    // Active__c is a formula that already evaluates TODAY() between ExhaustionDate__c and Replenishment_Date__c.
    List<Exhaustion__c> exRows = [
        SELECT Id,
               ExhaustionDate__c,
               Replenishment_Date__c,
               Active__c,
               Custodial_Account__c
        FROM Exhaustion__c
        WHERE Custodial_Account__c = :c.Custodial_Account__c
          AND Active__c = TRUE
        ORDER BY Replenishment_Date__c ASC NULLS LAST, ExhaustionDate__c ASC NULLS LAST
        LIMIT 500
    ];

    Id recommendedId = null;
    Date nearestRepl = null;

    for (Exhaustion__c ex : exRows) {
        // Build the option label prioritizing the annuity (replenishment) date
        String replTxt = (ex.Replenishment_Date__c != null) ? String.valueOf(ex.Replenishment_Date__c) : 'No Replenishment';
        String exTxt   = (ex.ExhaustionDate__c != null)     ? String.valueOf(ex.ExhaustionDate__c)     : 'No Exhaustion';
        String lbl = 'Annuity ' + replTxt; //+ ' (Exhaustion ' + exTxt + ') — Active';

        out.options.add(new OptionDTO(lbl, String.valueOf(ex.Id)));

        // Determine recommendedId as the ACTIVE exhaustion with the nearest Replenishment date
        // (The list is already ordered, but we compute explicitly for clarity)
        if (ex.Replenishment_Date__c != null && (nearestRepl == null || ex.Replenishment_Date__c < nearestRepl)) {
            nearestRepl = ex.Replenishment_Date__c;
            recommendedId = ex.Id;
        }
    }

    // If there are no active rows, recommendedId remains null
    out.recommendedId = recommendedId;
    return out;
}



    /**
     * Persists the selected Exhaustion__c into Case.trm_Exhaustion__c.
     * If exhaustionId is null, it clears the field.
     */
    @AuraEnabled
    public static void setCaseExhaustion(Id caseId, Id exhaustionId) {
        if (caseId == null) throw new AuraHandledException('Missing caseId.');

        // Security & FLS on Case
        Schema.DescribeSObjectResult cd = Case.SObjectType.getDescribe();
        if (!cd.isAccessible()) throw new AuraHandledException('No access to Case.');
        Map<String, Schema.SObjectField> fmap = cd.fields.getMap();
        final String TARGET = 'trm_Exhaustion__c';
        if (!fmap.containsKey(TARGET))
            throw new AuraHandledException('Field ' + TARGET + ' not found on Case.');
        if (!fmap.get(TARGET).getDescribe().isUpdateable())
            throw new AuraHandledException('No FLS to update ' + TARGET + '.');

        // Optional: validate Exhaustion Id belongs to same Member Account (defensive)
        if (exhaustionId != null) {
            // Check access to Exhaustion__c
            Schema.DescribeSObjectResult ed = Exhaustion__c.SObjectType.getDescribe();
            if (!ed.isAccessible()) throw new AuraHandledException('No access to Exhaustion__c.');
            Integer exists = [SELECT COUNT() FROM Exhaustion__c WHERE Id = :exhaustionId];
            if (exists == 0) throw new AuraHandledException('Invalid Exhaustion Id.');
        }

        update new Case(
            Id = caseId,
            trm_Exhaustion__c = exhaustionId
        );
    }

    @AuraEnabled(cacheable=false)
    public static Map<String, Object> validateBELAdmin(Id caseId) {
        Map<String, Object> result = new Map<String, Object>{
            'hasAdministration' => false,
            'hasFullAddress' => false,
            'missingFields' => new List<String>(),
            'administrationId' => null
        };
        if (caseId == null) return result;

        Case c = [SELECT Id, Administration__c FROM Case WHERE Id = :caseId LIMIT 1];
        if (c.Administration__c == null) return result;

        result.put('hasAdministration', true);
        result.put('administrationId', c.Administration__c);

        Administration__c a = [
            SELECT Id,
                AdminBEL_Address__c,
                AdminBEL_Address__CountryCode__s,
                AdminBEL_Address__StateCode__s
            FROM Administration__c
            WHERE Id = :c.Administration__c
            LIMIT 1
        ];

        System.Address addr = a.AdminBEL_Address__c;
        List<String> missing = new List<String>();

        if (addr == null || String.isBlank(addr.street))     missing.add('Street');
        if (addr == null || String.isBlank(addr.city))       missing.add('City');
        if (addr == null || String.isBlank(addr.postalCode)) missing.add('Postal Code');

        Boolean hasState   = !String.isBlank(a.AdminBEL_Address__StateCode__s)
                            || (addr != null && !String.isBlank(addr.state));
        Boolean hasCountry = !String.isBlank(a.AdminBEL_Address__CountryCode__s)
                            || (addr != null && !String.isBlank(addr.country));

        if (!hasState)   missing.add('State');
        if (!hasCountry) missing.add('Country');

        if (missing.isEmpty()) {
            result.put('hasFullAddress', true);
        } else {
            result.put('missingFields', missing);
        }
        return result;
    }

    // DocumentRequestController.cls (REPLACE existing method)
    @AuraEnabled
    public static void updateAdministrationAddress(
        Id adminId,
        String street,
        String city,
        String state,          // State/Province CODE (e.g., "CA")
        String postalCode,
        String countryCodeOpt  // Country CODE (e.g., "US")
    ) {
        if (adminId == null) throw new AuraHandledException('Missing Administration Id.');

        // Normalize and enforce both codes
        String cc = (countryCodeOpt == null ? '' : countryCodeOpt.trim().toUpperCase());
        String sc = (state == null ? '' : state.trim().toUpperCase());

        if (String.isBlank(cc)) throw new AuraHandledException('Country is required when specifying a state.');
        if (String.isBlank(sc)) throw new AuraHandledException('State is required.');

        // Minimal server-side validation: ensure the State code exists and is enabled in this org
        Map<String,String> orgStates = new Map<String,String>();
        for (Schema.PicklistEntry pe : User.StateCode.getDescribe().getPicklistValues()) {
            if (pe.isActive()) orgStates.put(pe.getValue(), pe.getLabel());
        }
        if (!orgStates.containsKey(sc)) {
            throw new AuraHandledException('The selected State is not enabled in this org.');
        }

        // Persist both *Code__s fields to respect State & Country Picklists
        update new Administration__c(
            Id = adminId,
            AdminBEL_Address__Street__s      = street,
            AdminBEL_Address__City__s        = city,
            AdminBEL_Address__PostalCode__s  = postalCode,
            AdminBEL_Address__StateCode__s   = sc,
            AdminBEL_Address__CountryCode__s = cc
        );
    }



@AuraEnabled(cacheable=true)
public static Map<String, String> getCountryCodeToLabelMap() {
    Map<String, String> out = new Map<String, String>();
    Schema.DescribeFieldResult df = Account.BillingCountryCode.getDescribe();
    for (Schema.PicklistEntry pe : df.getPicklistValues()) {
        out.put(pe.getValue(), pe.getLabel()); // "US" -> "United States"
    }
    return out;
}


@AuraEnabled(cacheable=true)
public static Map<String, String> getStateCodeToLabelMap(String countryCode) {
    // Fallback estable: NO usa getControllerValues() / getValidFor()
    Map<String, String> out = new Map<String, String>();
    Schema.DescribeFieldResult stateDf = Account.BillingStateCode.getDescribe();
    for (Schema.PicklistEntry pe : stateDf.getPicklistValues()) {
        out.put(pe.getValue(), pe.getLabel()); // "CA" -> "California"
    }
    return out;
}

    @AuraEnabled
    public static void setCaseLRDates(Id caseId, Date dateIssued, Date datePriorIssued) {
        if (caseId == null) {
            throw new AuraHandledException('Missing Case Id');
        }
        Case c = new Case(
            Id = caseId,
            LR_Date_Issued__c = dateIssued,
            LR_Prior_Dispute_Issued__c = datePriorIssued
        );
        update c;
    }

}