import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecordNotifyChange } from 'lightning/uiRecordApi';
import { isConsoleNavigation, openTab } from 'lightning/platformWorkspaceApi';
import { CloseActionScreenEvent } from 'lightning/actions';
import fetchDepartments from '@salesforce/apex/DocumentRequestController.fetchDepartments';
import fetchSubDepartments from '@salesforce/apex/DocumentRequestController.fetchSubDepartments';
import fetchSubDepartmentsByDepartment from '@salesforce/apex/DocumentRequestController.fetchSubDepartmentsByDepartment';
import fetchDocumentsUnified from '@salesforce/apex/DocumentRequestController.fetchDocumentsUnified';
import searchMappingsByName from '@salesforce/apex/DocumentRequestController.searchMappingsByName';
import mergeWithMapping from '@salesforce/apex/DocumentRequestController.mergeWithMapping';
// getDocumentRuleInfo removed - DOC_RULES now handled in JavaScript
// generateWithEnhancedFeatures - simple wrapper around production mergeWithMapping
import updateCaseTemplateFields from '@salesforce/apex/DocumentRequestController.updateCaseTemplateFields';
import updateAgentFields from '@salesforce/apex/DocumentRequestController.updateAgentFields';
import mergeAndReturnFile from '@salesforce/apex/DocumentRequestController.mergeAndReturnFile';
import fetchClaims from '@salesforce/apex/DocumentRequestController.fetchClaims';
import updateSelectedClaims from '@salesforce/apex/DocumentRequestController.updateSelectedClaims';
import fetchPayeeAddresses from '@salesforce/apex/DocumentRequestController.fetchPayeeAddresses';
import setCaseAddress from '@salesforce/apex/DocumentRequestController.setCaseAddress';
import searchCodes from '@salesforce/apex/DocumentRequestController.searchCodes';
import updateCaseDiagnosisCodes from '@salesforce/apex/DocumentRequestController.updateCaseDiagnosisCodes';
import fetchDiagnosisContextForCase
  from '@salesforce/apex/DocumentRequestController.fetchDiagnosisContextForCase';
import searchCodesByType
  from '@salesforce/apex/DocumentRequestController.searchCodesByType';
  import searchIcdCodes from '@salesforce/apex/DocumentRequestController.searchIcdCodes';
  import updateDiagnosisCodes from '@salesforce/apex/DocumentRequestController.updateDiagnosisCodes';










export default class DocumentRequestModal extends NavigationMixin(LightningElement) {
    @api recordId;

    // Component version for debugging
    VERSION = 'v2.2.0';

    // UI state
    @track step = 1;
    @track headerSubtitle = 'Pick a department or search directly';


    @track selectedClaimIds = [];

    // DOC_RULES - Complete JavaScript array with all 10 rules
    // CRITICAL: More specific patterns MUST come before general patterns!
    DOC_RULES = [
        // 1. Email Template - Revision - WC - Southern California Edison (MUST COME FIRST!)
        {
            match: 'email template - revision - wc - southern california edison',
            targetFieldApi: 'trm_Edison_Template__c',
            checkboxFieldApi: 'trm_Edison_Checkbox__c',
            baseLines: [
                'Revised Medicare Set-Aside Cost Driver Analysis Report',
                'Revised Medicare Set-Aside Allocation'
            ],
            options: [
                { key:'add-nq', label:'Add "Revised Non-Qualified Medical Expense Cost Projection"', lines:['Revised Non-Qualified Medical Expense Cost Projection'], affectsCheckbox:true }
            ]
        },
        // 2. Email Template - Revision - WC (MUST COME AFTER Edison rule!)
        {
            match: 'email template - revision - wc',
            targetFieldApi: 'trm_WC_Template__c',
            checkboxFieldApi: 'trm_WC_Checkbox__c',
            baseLines: [
                'Revised Medicare Set-Aside Cost Driver Analysis Report',
                'Revised Medicare Set-Aside Allocation',
                'Professional Administration Services Flyer'
            ],
            options: [
                { key:'add-rev-nq', label:'Add "Revised Non-Qualified Medical Expense Cost Projection"', lines:['Revised Non-Qualified Medical Expense Cost Projection'], affectsCheckbox:true }
            ]
        },
        // 3. Email Template - Revision - Liability
        {
            match: 'email template - revision - liability',
            targetFieldApi: 'Email_Template_Liability__c',
            baseLines: [
                'Revised Medicare Set-Aside Cost Driver Analysis Report',
                'Revised Medicare Set-Aside Allocation Report',
                'Professional Administration Services Flyer'
            ],
            options: [
                { key:'add-nq-report', label:'Add "Revised Non-Qualified Medical Expenses Report"', lines:['Revised Non-Qualified Medical Expenses Report'] },
                { key:'add-apportionment', label:'Add "Revised Medicare Set-Aside Apportionment Letter"', lines:['Revised Medicare Set-Aside Apportionment Letter'] }
            ]
        },
        // 4. Recommendation - MSA - Prof Admin - Liability - To ATTD
        {
            match: 'recommendation - msa - prof admin - liability - to attd',
            targetFieldApi: 'trm_Profesional_Admin_Template__c',
            checkboxFieldApi: 'trm_Profesional_Admin_Checkbox__c',
            baseLines: [
                'Medicare Set-Aside Cost Driver Analysis Report',
                'Medicare Set-Aside Allocation',
                'Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language',
                'Professional Administration Services Flyer'
            ],
            options: [
                { key:'add-nq', label:'Add "Non-Qualified Medical Expense Cost Projection"', lines:['Non-Qualified Medical Expense Cost Projection'], affectsCheckbox:true }
            ]
        },
        // 5. Recommendation - MSA - Prof Admin - Liability - No Apportionment
        {
            match: 'recommendation - msa - prof admin - liability - no apportionment',
            targetFieldApi: 'trm_Profesional_Admin_Template__c',
            checkboxFieldApi: 'trm_Profesional_Admin_Checkbox__c',
            baseLines: [
                'Medicare Set-Aside Cost Driver Analysis Report',
                'Medicare Set-Aside Allocation',
                'Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language',
                'Professional Administration Services Flyer'
            ],
            options: [
                { key:'add-nq', label:'Add "Non-Qualified Medical Expense Cost Projection"', lines:['Non-Qualified Medical Expense Cost Projection'], affectsCheckbox:true }
            ]
        },
        // 6. Recommendation Package - MSA Recommendation Letter - Professional Admin - WC
        {
            match: 'recommendation package - msa recommendation letter - professional admin - wc',
            targetFieldApi: 'trm_Profesional_Admin_Template__c',
            checkboxFieldApi: 'trm_Profesional_Admin_Checkbox__c',
            baseLines: [
                'Medicare Set-Aside Cost Driver Analysis Report',
                'Medicare Set-Aside Allocation',
                'Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language',
                'Professional Administration Services Flyer'
            ],
            options: [
                { key:'add-nq', label:'Add "Non-Qualified Medical Expense Cost Projection"', lines:['Non-Qualified Medical Expense Cost Projection'], affectsCheckbox:true }
            ]
        },
        // 7. Recommendation - MSA - Self Admin - Liability
        {
            match: 'recommendation - msa - self admin - liability',
            targetFieldApi: 'trm_Self_Admin_Template__c',
            checkboxFieldApi: 'trm_Self_Admin_Checkbox__c',
            baseLines: [
                'Medivest Invoice for Medicare Set-Aside Allocation',
                'Medicare Set-Aside Allocation',
                'Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language',
                'Self-Administration Kit Fee Quote'
            ],
            options: [
                { key:'add-nq', label:'Add "Non-Qualified Medical Expense Cost Projection"', lines:['Non-Qualified Medical Expense Cost Projection'], affectsCheckbox:true }
            ]
        },
        // 8. Recommendation - MSA - Self Admin - WC
        {
            match: 'recommendation - msa - self admin - wc',
            targetFieldApi: 'trm_Self_Admin_Template__c',
            checkboxFieldApi: 'trm_Self_Admin_Checkbox__c',
            baseLines: [
                'Medivest Invoice for Medicare Set-Aside Allocation',
                'Medicare Set-Aside Allocation',
                'Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language',
                'Self-Administration Kit Fee Quote'
            ],
            options: [
                { key:'add-nq', label:'Add "Non-Qualified Medical Expense Cost Projection"', lines:['Non-Qualified Medical Expense Cost Projection'], affectsCheckbox:true }
            ]
        },
        // 9. Recommendation Package - Revision - Liability - With Apportionment
        {
            match: 'recommendation package - revision - liability - with apportionment',
            targetFieldApi: 'trm_Apportionment_Template__c',
            baseLines: [
                'Revised Medicare Set-Aside Cost Driver Analysis Report',
                'Revised Medicare Set-Aside Allocation Report',
                'Revised Medicare Set-Aside Apportionment Letter',
                'Professional Administration Services Flyer'
            ],
            options: [
                { key:'add-rev-nq-report', label:'Add "Revised Non-Qualified Medical Expenses Report"', lines:['Revised Non-Qualified Medical Expenses Report'] }
            ]
        },
        // 10. Recommendation Package - Revision - Liability - No Apportionment (UPDATED per Ray's feedback)
        {
            match: 'recommendation package - revision - liability - no apportionment',
            targetFieldApi: 'trm_No_Apportionment_Template__c',
            checkboxFieldApi: 'trm_No_Apportionment_Checkbox__c',
            baseLines: [
                'Revised Medicare Set-Aside Cost Driver Analysis Report',
                'Revised Medicare Set-Aside Allocation Report',
                'Professional Administration Services Flyer'
            ],
            options: [
                { key:'add-rev-nq-report', label:'Add "Revised Non-Qualified Medical Expenses Report"', lines:['Revised Non-Qualified Medical Expenses Report'], affectsCheckbox:true }
            ]
        },
        // XX. Cover Letter - CMS Submission - Carrier Letter
        // Advanced document: multi-select Supporting_Claims__c
        {
          match: "cover letter - cms submission - carrier letter",
          baseLines: [],
          options: [],
          inputs: [], // claims are handled by a dedicated section, not generic inputs
        },
        {
          match: "email template - requesting comorbidities from broker",
          baseLines: [],
          options: [],
          inputs: [], // claims are handled by a dedicated section, not generic inputs
        },
        {
          match: "email template - requesting comorbidities from kevin puckett",
          baseLines: [],
          options: [],
          inputs: [], // claims are handled by a dedicated section, not generic inputs
        },
        {
        match: "cover letter - cms submission - submitter letter",
        baseLines: [],
        options: [],
        inputs: [
            {
            key: "addressToUse",
            label: "Select Entity Address",
            type: "picklist",
            required: true,
            values: [],
            }
        ],
        },
    ];

    // JavaScript DOC_RULES helper methods
    normalizeTemplateName(templateName) {
        if (!templateName) return '';
        return templateName
            .toLowerCase()
            .trim()
            .replace(/\s+/g, ' '); // Multiple spaces → single space
    }

    findMatchingRule(templateName) {
        if (!templateName) return null;

        const normalizedName = this.normalizeTemplateName(templateName);

        for (const rule of this.DOC_RULES) {
            if (rule.match === normalizedName) {
                return rule;
            }
        }
        return null;
    }

    generateTemplateContent(rule, selectedOptions) {
        if (!rule) return '';

        // SIMPLE FIX: Separate "Professional Administration Services Flyer" from other lines
        const flyerLines = rule.baseLines.filter(line =>
            line.includes('Professional Administration Services Flyer'));
        const nonFlyerLines = rule.baseLines.filter(line =>
            !line.includes('Professional Administration Services Flyer'));

        let allLines = [...nonFlyerLines];

        // Add optional content based on selected options
        if (selectedOptions && selectedOptions.length > 0) {
            for (const option of rule.options) {
                if (selectedOptions.includes(option.key)) {
                    allLines = allLines.concat(option.lines);
                }
            }
        }

        // ALWAYS put "Professional Administration Services Flyer" LAST
        allLines = allLines.concat(flyerLines);

        return allLines.join('\n');
    }

    @track searchTerm = '';
    @track loading = false;
    @track loadingMessage = 'Generating...';

    // data
    @track departments = [];      // [{label,value,className}]
    @track subDepartments = [];   // idem
    @track templates = [];        // [{id,name,className}]

    // selections
    @track selectedDepartment;
    @track selectedSubDepartment;
    @track selectedTemplateId;
    @track selectedTemplateName;

    // step4
    @track optionalContent = '';

    // DOC_RULES advanced document properties
    @track selectedOptions = [];
    @track isAdvancedDocument = false;
    @track detailsTextHtml = '';
    @track detailsOptions = [];
    @track currentRule = null; // Store current DOC_RULE for generation

    /* CLAIMS */
    @track claimRecords = [];      // [{ id, label }]

    get isClaimDoc() {
      const m = this.currentRule?.match;
      return (m === "cover letter - cms submission - carrier letter" || 
        m === "email template - requesting comorbidities from broker" ||
        m === "email template - requesting comorbidities from kevin puckett");
    }

    get hasClaims() {
      return this.claimRecords && this.claimRecords.length > 0;
    }
    /* END CLIMS */

    // Dynamic inputs support (Submitter Letter: address + diagnosis lookup)
    @track currentInputs = [];  // Configuration for advanced inputs based on DOC_RULES
    @track valuesByKey = {};    // Stores user-entered values by input key
    @track codeOptions = [];    // Dynamic options for diagnosis code lookup (search results)
    _codeSearchDebounce;        // Debounce handler for diagnosis code search

    @track diagnosisContext;   // { hasDiagnosis, icd9Label, icd10Label, ... }


    // ICD-9 UI state
    @track icd9SearchText = '';
    @track icd9Options = [];
    _icd9Debounce;

    // ICD-10 UI state
    @track icd10SearchText = '';
    @track icd10Options = [];
    _icd10Debounce;



    get hasIcd9Options() {
    return Array.isArray(this.icd9Options) && this.icd9Options.length > 0;
    }
    get icd9ComboboxClass() {
        return this.hasIcd9Options ? 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open'
                                : 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click';
    }

    get hasIcd10Options() {
        return Array.isArray(this.icd10Options) && this.icd10Options.length > 0;
    }
    get icd10ComboboxClass() {
        return this.hasIcd10Options ? 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click slds-is-open'
                                    : 'slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click';
    }


    // True when there are advanced inputs to render for the current rule
    get hasDynamicInputs() {
        return Array.isArray(this.currentInputs) && this.currentInputs.length > 0;
    }

    get inputsWithValues() {
        const src = this.currentInputs || [];
        const map = this.valuesByKey || {};

        return src.map((inp) => {
            const base = {
                ...inp,
                // Current value for this logical key (addressToUse, diagnosisCodeId, etc.)
                value: map[inp.key] ?? null,

                // For non-picklist inputs this will be used by <lightning-input>
                _renderType: inp.type,

                // Flags to drive template rendering
                _isPicklist: inp.type === "picklist",
                _isCombo: inp.type === "picklist", // 👈 IMPORTANT: enables <lightning-combobox> branch
                _isLookup: inp.type === "lookup",

                _options: null,
                _placeholder: null,
            };

            if (inp.type === "picklist") {
                // Options for <lightning-combobox>
                base._options = Array.isArray(inp.values) ? inp.values : [];
            }

            if (inp.type === "lookup") {
                // Lookup uses a search input and a dropdown
                base._placeholder = "Type to search diagnosis...";
                base.displayValue = map.diagnosisSearch || "";
            }

            return base;
        });
    }


    get hasCodeOptions() {
        return Array.isArray(this.codeOptions) && this.codeOptions.length > 0;
    }

    get lookupComboboxClass() {
        // Open dropdown when there are search results
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${
            this.hasCodeOptions ? "slds-is-open" : ""
        }`;
    }

    get isLookupMissing() {
        // Used for basic validation feedback if needed in template (optional)
        return (
            this.currentInputs.some(
                (i) => i.key === "diagnosisCodeId" && i.required
            ) && !this.valuesByKey?.diagnosisCodeId
        );
    }

    // Helper to know when this is the Submitter Letter template
    get isSubmitterLetterDoc() {
        return (
            this.currentRule?.match ===
            "cover letter - cms submission - submitter letter"
        );
    }

    
    get showRichText() {
        // Show rich text ONLY when:
        // - It is an advanced document
        // - The rule actually has baseLines
        return (
            this.isAdvancedDocument &&
            this.currentRule &&
            Array.isArray(this.currentRule.baseLines) &&
            this.currentRule.baseLines.length > 0
        );
    }

    get showDetailsOptions() {
        // Show DOC_RULE checkboxes ONLY when:
        // - It is an advanced document
        // - The rule has options
        return (
            this.isAdvancedDocument &&
            Array.isArray(this.detailsOptions) &&
            this.detailsOptions.length > 0
        );
    }



    // stepper classes (precalculadas — nada de llamadas en template)
    get step1Class() { return 'step ' + (this.step >= 1 ? 'active' : ''); }
    get step2Class() { return 'step ' + (this.step >= 2 ? 'active' : ''); }
    get step3Class() { return 'step ' + (this.step >= 3 ? 'active' : ''); }
    get step4Class() { return 'step ' + (this.step >= 4 ? 'active' : ''); }

    // visibility
    get showStep1() { return this.step === 1; }
    get showStep2() { return this.step === 2; }
    get showStep3() { return this.step === 3; }
    get showStep4() { return this.step === 4; }

    get hasDepartments()    { return this.departments && this.departments.length > 0; }
    get hasSubDepartments() { return this.subDepartments && this.subDepartments.length > 0; }
    get hasTemplates()      { return this.templates && this.templates.length > 0; }

    connectedCallback() {
        console.log('[DocumentRequestModal] Component initialized - Version:', this.VERSION);
        this.loadDepartments();
    }

    // -------- Search ----------
    onSearchInput = (e) => { this.searchTerm = e.target.value; };
    onSearchKeydown = (e) => { if (e.key === 'Enter') this.doSearch(); };
    async doSearch() {
        const term = (this.searchTerm || '').trim();

        // Validate search term is not empty
        if (!term) {
            this.showToast('Search Required', 'Please enter a search term', 'warning');
            return;
        }

        const rows = await searchMappingsByName({ term });

        this.templates = (rows || []).map(r => ({
            id: r.Id,
            name: r.Name,
            className: 'pill'
        }));

        // Only advance to step 3 if results found
        if (this.templates.length > 0) {
            this.step = 3;
            this.headerSubtitle = `Search results for "${term}"`;
        } else {
            // Stay on current step and show clear message
            this.showToast('No Results', `No documents found matching "${term}"`, 'info');
            this.step = 1;
            this.headerSubtitle = 'No results found - try another search or browse by category';
        }

        // Clear search field after search execution
        this.searchTerm = '';
        // Clear previous selection
        this.selectedTemplateId = undefined;
        this.selectedTemplateName = undefined;
        this.markSelectedInArray(this.templates, 'id', this.selectedTemplateId);
    }

    // -------- Step 1 ----------
    async loadDepartments() {
        const rows = await fetchDepartments();
        this.departments = (rows || []).map(r => ({
            label: r, value: r, className: 'pill'
        }));
        this.step = 1;
        this.headerSubtitle = 'Pick a department or use search';
    }
    pickDepartment = (e) => {
        const val = e.currentTarget.dataset.value;
        this.selectedDepartment = val;
        this.markSelectedInArray(this.departments, 'value', val);
        this.searchTerm = '';
        this.loadSubDepartments(val);
    };

    // -------- Step 2 ----------
    async loadSubDepartments(dept) {
        // Use filtered method to get only sub-departments with documents in this department
        const rows = await fetchSubDepartmentsByDepartment({ department: dept });
        const subDepts = (rows || []).map(r => ({
            label: r, value: r, className: 'pill'
        }));
        // Add "All" option at the beginning
        this.subDepartments = [
            { label: 'All', value: 'All', className: 'pill' },
            ...subDepts
        ];
        // Siempre mostramos paso 2; si sólo está 'All', el usuario puede saltar.
        this.step = 2;
        this.headerSubtitle = `Department: ${dept}`;
    }
    pickSubDepartment = async (e) => {
        const val = e.currentTarget.dataset.value;
        this.selectedSubDepartment = val;
        this.markSelectedInArray(this.subDepartments, 'value', val);
        this.searchTerm = '';
        await this.loadTemplates();
    };

    // -------- Step 3 ----------
    async loadTemplates() {
        const dept = this.selectedDepartment;
        const sub  = this.selectedSubDepartment;

        // Use production fetchDocumentsUnified method
        const departmentInputs = [dept];
        const subDepartmentNames = sub && sub !== 'All' ? [sub] : ['All'];

        const result = await fetchDocumentsUnified({
            departmentInputs: departmentInputs,
            subDepartmentNames: subDepartmentNames
        });

        this.templates = (result.rows || []).map(r => ({
            id: r.Id, name: r.Name, className: 'pill'
        }));
        this.step = 3;
        this.headerSubtitle = `Department: ${dept}${sub && sub !== 'All' ? ' / ' + sub : ''}`;
        // limpiar selección visual
        this.selectedTemplateId = undefined;
        this.selectedTemplateName = undefined;
        this.markSelectedInArray(this.templates, 'id', this.selectedTemplateId);
    }
    pickTemplate = async (e) => {
        const id = e.currentTarget.dataset.id;
        this.selectedTemplateId = id;
        this.markSelectedInArray(this.templates, 'id', id);
        // Get template name from templates array
        const template = this.templates.find(t => t.id === id);
        this.selectedTemplateName = template ? template.name : '';

        // Reset advanced document state
        this.resetAdvancedDocumentState();

        // Check for DOC_RULES using JavaScript logic
        const rule = this.findMatchingRule(this.selectedTemplateName);
        if (rule) {
            // Advanced document detected
            this.isAdvancedDocument = true;
            this.detailsTextHtml = this.generateTemplateContent(rule, []).replace(/\n/g, '<br>');
            this.detailsOptions = rule.options || [];
            this.currentRule = rule; // Store for generation

            // Initialize dynamic inputs from DOC_RULES definition (if any)
            // NOTE: We clone the array to avoid accidentally mutating the static DOC_RULES config
            this.currentInputs = Array.isArray(rule.inputs)
                ? rule.inputs.map(i => ({ ...i }))
                : [];
            this.valuesByKey = {};
            this.codeOptions = [];
            
            // --- Carrier Letter: load Supporting_Claims__c related to this record ---
            if (
              this.isCase &&
              (rule.match ===
                "cover letter - cms submission - carrier letter" ||
                rule.match ===
                  "email template - requesting comorbidities from broker" ||
                rule.match ===
                  "email template - requesting comorbidities from kevin puckett")
            ) {
              try {
                const rows = await fetchClaims({ parentId: this.recordId });

                this.claimRecords = (rows || []).map((r) => {
                  const pieces = [];

                  // Nombre del claim
                  if (r.Name) {
                    pieces.push(r.Name);
                  }

                  // DOI
                  if (r.Date_of_Injury__c) {
                    pieces.push(`DOI: ${r.Date_of_Injury__c}`);
                  }

                  // Accepted / Denied usando el TEXTO de los campos
                  const statusParts = [];

                  if (r.Accepted_Claimed__c) {
                    statusParts.push(`Accepted: ${r.Accepted_Claimed__c}`);
                  }

                  if (r.Denied__c) {
                    statusParts.push(`Denied: ${r.Denied__c}`);
                  }

                  if (statusParts.length) {
                    pieces.push(statusParts.join(" • ")); // o ' | ' si te gusta más
                  }

                  return {
                    id: r.Id,
                    label: pieces.join(" • "), // 👈 lo que verá el usuario junto al checkbox
                    name: r.Name,
                    dateOfInjury: r.Date_of_Injury__c,
                    accepted: r.Accepted_Claimed__c,
                    denied: r.Denied__c,
                  };
                });

                this.selectedClaimIds = [];
              } catch (err) {
                console.warn(
                  "Failed to fetch Supporting_Claims__c records:",
                  err
                );
                this.claimRecords = [];
                this.selectedClaimIds = [];
              }
            }

            // --- Submitter Letter: load Payee addresses into "addressToUse" picklist ---
            if (this.isCase && rule.match === "cover letter - cms submission - submitter letter") {
                try {
                    // Fetch Billing / Mailing / Main addresses from Payee_Name__c via Apex
                    const opts = await fetchPayeeAddresses({ caseId: this.recordId });

                    const addressOptions = (opts || []).map(o => ({
                        label: o.label,
                        value: o.value
                    }));

                    // Inject options into the "addressToUse" input from DOC_RULES
                    const idx = this.currentInputs.findIndex(i => i.key === "addressToUse");
                    if (idx >= 0) {
                        this.currentInputs[idx] = {
                            ...this.currentInputs[idx],
                            type: 'picklist',
                            values: addressOptions,
                            required: true
                        };
                    }

                    this.diagnosisContext = await fetchDiagnosisContextForCase({
                        caseId: this.recordId
                    });

                    // Pre-fill search text with current labels (if any)
                    if (this.diagnosisContext?.icd9Label) {
                        this.icd9SearchText = this.diagnosisContext.icd9Label;
                        this.currentIcd9Id = this.diagnosisContext.icd9Id;
                        this.originalIcd9Id = this.diagnosisContext.icd9Id;
                    }
                    if (this.diagnosisContext?.icd10Label) {
                        this.icd10SearchText = this.diagnosisContext.icd10Label;
                        this.currentIcd10Id = this.diagnosisContext.icd10Id;
                        this.originalIcd10Id = this.diagnosisContext.icd10Id;
                    }


                } catch (err) {
                    // Do not break the flow if address loading fails; just log and clear options
                    console.warn('Failed to fetch Payee addresses for Submitter Letter or Diagnosis Context', err);
                    const idx = this.currentInputs.findIndex(i => i.key === "addressToUse");
                    if (idx >= 0) {
                        this.currentInputs[idx] = {
                            ...this.currentInputs[idx],
                            values: []
                        };
                    }
                }
            }


            console.log('Advanced document detected:', this.selectedTemplateName);
        } else {
            // Simple document
            console.log('Simple document (no DOC_RULES):', this.selectedTemplateName);
        }

        
        this.step = 4;
        this.headerSubtitle = `Document: ${this.selectedTemplateName}`;
        // limpiar opcional
        this.optionalContent = '';
    };

    // -------- Step 4 ----------
    onOptionalChange = (e) => { this.optionalContent = e.target.value; };
    goBackToDocs = () => { this.step = 3; };

    // -------- DOC_RULES Advanced Document Methods ----------
    handleRichTextChange = (e) => {
        this.detailsTextHtml = e.target.value;
    };

    handleOptionChange = (e) => {
        const optionKey = e.target.dataset.key;
        const isChecked = e.target.checked;

        if (isChecked) {
            if (!this.selectedOptions.includes(optionKey)) {
                this.selectedOptions = [...this.selectedOptions, optionKey];
            }
        } else {
            this.selectedOptions = this.selectedOptions.filter(opt => opt !== optionKey);
        }

        this.updateRichTextContent();
    };

    updateRichTextContent = () => {
        if (this.currentRule) {
            // Generate content using DOC_RULES structure
            const newContent = this.generateTemplateContent(this.currentRule, this.selectedOptions);
            this.detailsTextHtml = newContent.replace(/\n/g, '<br>');
        }
    };

    resetAdvancedDocumentState = () => {
        this.documentRuleInfo = null;
        this.selectedOptions = [];
        this.isAdvancedDocument = false;
        this.detailsTextHtml = '';
        this.detailsOptions = [];
        // Reset advanced input system
        this.currentInputs = [];
        this.valuesByKey = {};
        this.codeOptions = [];
    };


    // -------- Navigation Methods - Clickable Stepper ----------
    goToStep1 = () => {
        if (this.step > 1) {
            this.step = 1;
            this.headerSubtitle = 'Pick a department or search directly';
            // Clear subsequent selections to maintain data integrity
            this.selectedDepartment = undefined;
            this.selectedSubDepartment = undefined;
            this.selectedTemplateId = undefined;
            this.selectedTemplateName = undefined;
        }
    };

    goToStep2 = () => {
        if (this.step > 2 && this.selectedDepartment) {
            this.step = 2;
            this.headerSubtitle = `Department: ${this.selectedDepartment}`;
            // Clear subsequent selections
            this.selectedSubDepartment = undefined;
            this.selectedTemplateId = undefined;
            this.selectedTemplateName = undefined;
            this.searchTerm = '';
        }
    };

    goToStep3 = () => {
        if (this.step > 3 && this.selectedDepartment && this.selectedSubDepartment) {
            this.step = 3;
            this.headerSubtitle = `Sub-Department: ${this.selectedSubDepartment}`;
            // Clear subsequent selections
            this.selectedTemplateId = undefined;
            this.selectedTemplateName = undefined;
            this.searchTerm = '';
        }
    };

    goToStep4 = () => {
        // Step 4 is final step, no navigation needed
        if (this.step === 4) return;
    };

    // -------- Acciones ----------
    handleReset = () => {
        // Reset total
        this.step = 1;
        this.searchTerm = '';
        this.departments = [];
        this.subDepartments = [];
        this.templates = [];
        this.selectedDepartment = undefined;
        this.selectedSubDepartment = undefined;
        this.selectedTemplateId = undefined;
        this.selectedTemplateName = undefined;
        this.optionalContent = '';
        this.headerSubtitle = 'Pick a department or search directly';
        this.loadDepartments();
    };
    // Quick Action context detection - defensive programming for different deployment contexts
    isQuickAction() {
        // Quick Actions run in modal context with specific URL patterns or iframe detection
        return window.location.href.includes('modal') ||
               window.location.href.includes('action') ||
               window.parent !== window; // iframe detection
    }

    handleExit = () => {
        // TRINITY FIX v3: Silent exit - no toasts, no navigation, just reset
        console.log('🎯 TRINITY EXIT v3: X button clicked - silent reset only');

        // Always just silently reset the component state - no navigation, no toasts
        this.selectedDepartments = [];
        this.selectedSubDepartments = [];
        this.selectedDocuments = [];
        this.currentStep = 1;
        this.searchTerm = '';
        this.searchResults = [];
        this.showSearchResults = false;
        this.isLoading = false;
        this.showAdditionalDetails = false;
        this.additionalDetails = {};
        this.error = null;

        console.log('🎯 TRINITY EXIT v3: Component state reset complete - no toasts, no navigation');
    };

    async generate() {
        console.log('Generate method called!'); // Debug log
        console.log('selectedTemplateId:', this.selectedTemplateId);
        console.log('recordId:', this.recordId);

        if (!this.selectedTemplateId || !this.recordId) {
            this.showToast('Error', 'Missing template or record information.', 'error');
            return;
        }

        // Require at least one claim selected ONLY for the Carrier Letter template
        if (this.isClaimDoc && (!this.selectedClaimIds || this.selectedClaimIds.length === 0)) {
            this.showToast(
                'No claims selected',
                'Please select at least one claim to include in the document.',
                'warning'
            );
            return;
        }


        try {
            // Smooth loading state transition
            this.loading = true;
            this.loadingMessage = 'Preparing document...';

            // Small delay to ensure UI updates smoothly (eliminates flicker)
            await this.delay(100);

            console.log('Starting document generation...');
            console.log('Advanced document:', this.isAdvancedDocument);

            // STEP 1: ALWAYS populate agent fields (all objects)
            this.loadingMessage = 'Updating agent information...';
            try {
                await updateAgentFields({ recordId: this.recordId });
                console.log('Agent fields updated successfully');
            } catch (agentError) {
                console.warn('Failed to update agent fields:', agentError);
                // Continue with generation even if agent field update fails
            }


            let docId;
            const objectApiName = this.getObjectApiName();

            // STEP 2: Handle advanced documents (Case only)
            if (this.isAdvancedDocument && this.currentRule && this.isCase) {
                // Advanced document - update template fields then generate
                console.log('Using enhanced generation for advanced document');
                this.loadingMessage = 'Processing advanced document rules...';

                // Generate template content using JavaScript DOC_RULES
                const templateContent = this.generateTemplateContent(this.currentRule, this.selectedOptions);

                // Determine checkbox value
                let checkboxValue = false;
                if (this.selectedOptions && this.selectedOptions.length > 0) {
                    for (const option of this.currentRule.options) {
                        if (this.selectedOptions.includes(option.key) && option.affectsCheckbox) {
                            checkboxValue = true;
                            break;
                        }
                    }
                }

                // 🚨 MATT'S DEBUG: Edison Template Field Population Before WebMerge
                const isEdisonTemplate = (this.currentRule.targetFieldApi === 'trm_Edison_Template__c');
                if (isEdisonTemplate) {
                    console.log('🔥 EDISON DEBUG: About to populate trm_Edison_Template__c field BEFORE webmerge');
                    console.log('📝 Edison Template Content Details:');
                    console.log('  - Target Field: ' + this.currentRule.targetFieldApi);
                    console.log('  - Content Length: ' + (templateContent ? templateContent.length : 0) + ' characters');
                    console.log('  - Content Preview: "' + (templateContent ? templateContent.substring(0, 100) + '...' : 'NULL') + '"');
                    console.log('  - Checkbox Field: ' + this.currentRule.checkboxFieldApi);
                    console.log('  - Checkbox Value: ' + checkboxValue);
                    console.log('🎯 EDISON DEBUG: This field MUST be populated BEFORE webmerge payload is sent');
                }

                // Update case template fields before generation
                try {
                  // Only call when rule actually defines a target field
                  if (this.currentRule?.targetFieldApi) {
                      console.log('💾 Calling updateCaseTemplateFields (guarded)...');
                      await updateCaseTemplateFields({
                          caseId: this.recordId,
                          targetFieldApi: this.currentRule.targetFieldApi,
                          value: templateContent,
                          checkboxFieldApi: this.currentRule.checkboxFieldApi || null,
                          checkboxValue: checkboxValue
                      });
                      console.log('✅ Case template fields updated successfully');
                  } else {
                      console.log('ℹ️ No targetFieldApi in rule — skipping updateCaseTemplateFields');
                  }
                } catch (fieldError) {
                    console.warn('❌ Failed to update Case template fields:', fieldError);
                    if (isEdisonTemplate) {
                        console.error('🔥 EDISON DEBUG: CRITICAL - Edison template field population FAILED!');
                    }
                    // Continue with generation even if field update fails
                }

                // STEP 3: Generate document
                this.loadingMessage = 'Generating document...';
                console.log('🖥️ UI: About to call mergeWithMapping (production method)');

                // 🚨 MATT'S DEBUG: Critical timing validation for Edison template
                if (isEdisonTemplate) {
                    console.log('🎯 EDISON DEBUG: ===== CRITICAL TIMING VALIDATION =====');
                    console.log('🔥 EDISON DEBUG: trm_Edison_Template__c field has been populated');
                    console.log('🚀 EDISON DEBUG: About to send webmerge payload - field MUST be populated now');
                    console.log('📋 EDISON DEBUG: WebMerge will query Case record and should find populated field');
                    console.log('🎯 EDISON DEBUG: ===== END TIMING VALIDATION =====');
                }

                // 🚨 TRINITY WEBMERGE DEBUG: Log full object being sent to WebMerge
                const webmergePayload = {
                    mappingId: this.selectedTemplateId,
                    recordId: this.recordId,
                    objectApiName: objectApiName
                };
                console.log('🚀 TRINITY WEBMERGE DEBUG: Full payload being sent to mergeWithMapping:');
                console.log('📦 Payload Object:', JSON.stringify(webmergePayload, null, 2));
                console.log('🔍 Payload Details:');
                console.log('  - mappingId (selectedTemplateId):', webmergePayload.mappingId);
                console.log('  - recordId:', webmergePayload.recordId);
                console.log('  - objectApiName:', webmergePayload.objectApiName);

                if (isEdisonTemplate) {
                    console.log('🔥 EDISON DEBUG: Sending webmerge payload NOW - Edison field should be populated');
                }
                
                // --- Carrier Letter: persist selected Supporting_Claims__c into Case.Selected_Claims__c ---
                if (
                  this.currentRule &&
                  this.isCase &&
                  (
                    this.currentRule.match === "cover letter - cms submission - carrier letter" ||
                    this.currentRule.match === "email template - requesting comorbidities from broker" ||
                    this.currentRule.match === "email template - requesting comorbidities from kevin puckett"
                  )
                ) {
                  try {
                    await updateSelectedClaims({
                      recordId: this.recordId,
                      claimIds: this.selectedClaimIds || [],
                    });
                  } catch (e) {
                    console.warn("Failed to update selected claims:", e);
                    // Non-blocking: continue with merge even if this fails
                  }
                }

                // --- Submitter Letter: validate and persist address before merging ---
                if (this.isSubmitterLetterDoc && this.isCase) {
                    const addr = this.valuesByKey?.addressToUse || null;

                    if (!addr) {
                        this.showToast(
                            'Missing information',
                            'Please select an Address before generating this document.',
                            'warning'
                        );
                        this.loading = false;
                        return;
                    }

                    try {
                        // 1) Guardar la dirección en el Case
                        await setCaseAddress({
                            caseId: this.recordId,
                            address: addr
                        });

                        // 2) SIEMPRE actualizar ICD-9 / ICD-10 + trm_All_Diagnosis_Codes__c
                        await updateDiagnosisCodes({
                            caseId: this.recordId,
                            icd9Id: this.currentIcd9Id || null,
                            icd10Id: this.currentIcd10Id || null
                        });

                    } catch (e) {
                        console.warn('Failed to persist Submitter Letter address OR Diagnosis Codes', e);
                        this.showToast(
                            'Error',
                            this.errMsg(e) || 'Failed to save the Address OR Diagnosis Codes on the Case.',
                            'error'
                        );
                        this.loading = false;
                        return;
                    }
                }



                //docId = await mergeWithMapping(webmergePayload);

                // === BEGIN  immediate download  ===
                const payload = await mergeAndReturnFile({
                mappingId: this.selectedTemplateId,
                recordId: this.recordId,
                objectApiName: objectApiName
                });

                // 1) Download file
                this.downloadBase64File(payload.fileName, payload.mimeType, payload.base64Data);

                // 2) Preserve existing behavior using the same docId
                docId = payload.contentDocumentId;
                // === END ===



                // Clear template fields after generation (cleanup)
                try {
                    if (this.currentRule?.targetFieldApi) {
                        await updateCaseTemplateFields({
                            caseId: this.recordId,
                            targetFieldApi: this.currentRule.targetFieldApi,
                            value: null,
                            checkboxFieldApi: this.currentRule.checkboxFieldApi || null,
                            checkboxValue: false
                        });
                    } else {
                        console.log('ℹ️ No targetFieldApi in rule — skipping cleanup updateCaseTemplateFields');
                    }
                } catch (cleanupError) {
                    console.warn('Failed to clear template fields (guarded):', cleanupError);
                }

                console.log('🖥️ UI: mergeWithMapping returned docId =', docId);
            } else {
                // Simple document - use the production method
                console.log('Using basic generation for simple document');
                this.loadingMessage = 'Generating document...';
                console.log('🖥️ UI: About to call mergeWithMapping');
                console.log('🖥️ UI: mappingId =', this.selectedTemplateId);
                console.log('🖥️ UI: recordId =', this.recordId);

                // 🚨 TRINITY WEBMERGE DEBUG: Log full object being sent to WebMerge (Simple Document)
                const webmergePayload = {
                    mappingId: this.selectedTemplateId,
                    recordId: this.recordId,
                    objectApiName: objectApiName
                };
                console.log('🚀 TRINITY WEBMERGE DEBUG: Full payload being sent to mergeWithMapping (SIMPLE DOC):');
                console.log('📦 Payload Object:', JSON.stringify(webmergePayload, null, 2));
                console.log('🔍 Payload Details:');
                console.log('  - mappingId (selectedTemplateId):', webmergePayload.mappingId);
                console.log('  - recordId:', webmergePayload.recordId);
                console.log('  - objectApiName:', webmergePayload.objectApiName);

                //docId = await mergeWithMapping(webmergePayload);
                // === BEGIN patch: maintain behavior + add immediate download  ===
                const payload = await mergeAndReturnFile({
                mappingId: this.selectedTemplateId,
                recordId: this.recordId,
                objectApiName: objectApiName
                });

                // 1) Download NOW
                this.downloadBase64File(payload.fileName, payload.mimeType, payload.base64Data);

                // 2) Retain existing behavior
                docId = payload.contentDocumentId;
                // === END parche ===


                console.log('🖥️ UI: mergeWithMapping returned docId =', docId);
            }

            console.log('🖥️ UI: FINAL docId before file opening:', docId);

            if (docId) {
                // Update loading message
                this.loadingMessage = 'Completing...';
                await this.delay(200);

                // Refresh the host record view to show new file in Files related list
                this.refreshHostRecordView();

                // Show success toast with clickable link to document
                //this.showToastWithLink('Document Generated Successfully!', 'View Document', docId);
                this.showToast('Document Generated Successfully!', 'Please check your downloads folder', 'success');
            } else {
                this.showToast(
                    'Merge complete',
                    'No file was immediately available. Check the Files related list or mapping settings.',
                    'warning'
                );
            }

        } catch (error) {
            console.error('Document generation error:', error);
            const errorMessage = this.errMsg(error);
            this.showToast('Merge failed', errorMessage, 'error');
        } finally {
            // Smooth loading state transition
            this.loadingMessage = 'Completing...';
            await this.delay(300);
            this.loading = false;
        }
    }

    // Add missing showToast method
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Show success toast with clickable link to document
    showToastWithLink(title, linkLabel, docId) {
        const event = new ShowToastEvent({
            title: title,
            message: 'Your document is ready. {0}',
            messageData: [
                {
                    url: '/lightning/r/ContentDocument/' + docId + '/view',
                    label: linkLabel
                }
            ],
            variant: 'success'
        });
        this.dispatchEvent(event);
    }

    // Add errMsg helper from original production code
    errMsg(err) {
        try {
            if (typeof err === 'string') return err;
            if (err?.body?.message) return err.body.message;
            return JSON.stringify(err);
        } catch (e) {
            return 'Unexpected error';
        }
    }

    // ---------- Object Type Detection ----------
    get isCase() {
        return this.recordId?.startsWith('500');
    }

    getObjectApiName() {
        if (!this.recordId) return 'Case'; // Default fallback

        // Salesforce record ID prefixes for supported objects
        const prefixMap = {
            '500': 'Case',
            // Add other object prefixes as needed when team confirms them
            // 'XXX': 'Member_Account__c',
            // 'XXX': 'Administration__c',
            // 'XXX': 'Denied_Refund__c',
            // 'XXX': 'Entity__c'
        };

        const prefix = this.recordId.substring(0, 3);
        return prefixMap[prefix] || 'Case'; // Default to Case if unknown
    }

    // ---------- Helper methods for smooth UX ----------
    delay(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    // ---------- File handling helpers from production code ----------
    async openFileRecordWithRetry(docId, maxRetries = 3) {
        for (let attempt = 1; attempt <= maxRetries; attempt++) {
            try {
                await this.openFileRecord(docId);
                return true; // Success
            } catch (e) {
                console.warn(`File opening attempt ${attempt} failed:`, e);

                if (attempt < maxRetries) {
                    // Wait before retry with exponential backoff
                    const waitTime = Math.min(1000 * Math.pow(2, attempt - 1), 3000);
                    await this.delay(waitTime);
                } else {
                    // Final attempt failed, log but don't throw
                    console.error('All file opening attempts failed:', e);
                    return false;
                }
            }
        }
        return false;
    }

    async openFileRecord(docId) {
        try {
            console.log('🖥️ UI: openFileRecord called with docId =', docId);

            // Use the production pattern from original_webmerge.txt
            // Check if we're in console navigation first
            if (await isConsoleNavigation()) {
                console.log('🖥️ UI: Using console navigation to open docId =', docId);
                await openTab({ recordId: docId, focus: true });
            } else {
                console.log('🖥️ UI: Using standard navigation to open docId =', docId);
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: docId,
                        objectApiName: 'ContentDocument',
                        actionName: 'view'
                    }
                });
            }
        } catch (e) {
            console.error('Error opening file record:', e);
            // Fallback to file preview
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'filePreview' },
                state: { selectedRecordId: docId }
            });
        }
    }

    refreshHostRecordView() {
        try {
            // Use the proper LWC way to refresh record data
            getRecordNotifyChange([{ recordId: this.recordId }]);
        } catch (e) {
            console.warn('getRecordNotifyChange failed, trying legacy refresh:', e);
            try {
                // Fallback to legacy Aura refresh
                eval("$A.get('e.force:refreshView').fire();");
            } catch (e2) {
                console.warn('Legacy refresh also failed:', e2);
                // Final fallback - show message to user
                this.showToast('Info', 'Document generated. Please refresh the page to see the new file in the Files related list.', 'info');
            }
        }
    }

    // -------- util visual: marcar selección (sin llamadas en template) --------
    markSelectedInArray(arr, key, val) {
        if (!arr) return;
        arr.forEach(item => {
            const base = 'pill';
            item.className = (val && item[key] === val) ? (base + ' selected') : base;
        });
        // forzar reactividad
        if (arr === this.departments) this.departments = [...arr];
        if (arr === this.subDepartments) this.subDepartments = [...arr];
        if (arr === this.templates) this.templates = [...arr];
    }

        // ====== DOWNLOAD-IMMEDIATE SUPPORT ======
    downloadBase64File(fileName, mimeType, base64Data) {
        const byteChars = atob(base64Data);
        const byteNumbers = new Array(byteChars.length);
        for (let i = 0; i < byteChars.length; i++) byteNumbers[i] = byteChars.charCodeAt(i);
        const byteArray = new Uint8Array(byteNumbers);
        const blob = new Blob([byteArray], { type: mimeType });

        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = fileName || 'document';
        document.body.appendChild(a);
        a.click();
        a.remove();
        URL.revokeObjectURL(url);
    }
    // ====== /DOWNLOAD-IMMEDIATE SUPPORT ======



    handleClaimCheckboxChange = (e) => {
      const claimId = e.target.value;
      const checked = e.target.checked;

      let next = [...(this.selectedClaimIds || [])];

      if (checked) {
        // Add Id if it is not already present
        if (!next.includes(claimId)) {
          next.push(claimId);
        }
      } else {
        // Remove Id when unchecked
        next = next.filter(id => id !== claimId);
      }

      this.selectedClaimIds = next;
    };

    // Generic handler for dynamic inputs (text, picklist, etc.)
    handleDynamicInputChange = (event) => {
        const key = event.target.dataset.key;
        // For lightning-combobox use event.detail.value, for lightning-input use event.target.value
        const val = (event.detail && event.detail.value !== undefined)
            ? event.detail.value
            : event.target.value;

        // Store value by its logical key (addressToUse, diagnosisCodeId, etc.)
        this.valuesByKey = { ...(this.valuesByKey || {}), [key]: val || null };
    };

        // Simple debounce utility for diagnosis code search
    debounce(fn, wait) {
        return (...args) => {
            clearTimeout(this._codeSearchDebounce);
            this._codeSearchDebounce = setTimeout(() => fn.apply(this, args), wait);
        };
    }

        // Debounced search function for diagnosis codes
    searchCodesDebounced = this.debounce(async (term) => {
        try {
            const opts = await searchCodes({ term });
            // Map Apex DTOs to combobox-like options
            this.codeOptions = (opts || []).map(o => ({
                label: o.label,
                value: o.value
            }));
            // Force re-render of inputsWithValues
            this.currentInputs = [...this.currentInputs];
        } catch (e) {
            console.warn("Diagnosis search failed", e);
            this.codeOptions = [];
        }
    }, 250);

        // User is typing into the diagnosis search input
    handleLookupTyping = (event) => {
        const typed = (event.target.value || "").trim();

        // Store the visible search text separately
        this.valuesByKey = { ...this.valuesByKey, diagnosisSearch: typed };

        if (typed.length >= 2) {
            this.searchCodesDebounced(typed);
        } else {
            this.codeOptions = [];
        }
    };

    // User clicks a diagnosis option from the dropdown
    handleSelectCode = (event) => {
        const id = event.currentTarget.dataset.id;
        const label = event.currentTarget.dataset.label;

        // Store the selected Diagnosis Code Id and its label
        this.valuesByKey = {
            ...this.valuesByKey,
            diagnosisCodeId: id,
            diagnosisSearch: label
        };

        // Close dropdown
        this.codeOptions = [];
    };

    // Basic key handling on the search input (optional niceties)
    handleLookupKeydown = (event) => {
        if (event.key === "Escape") {
            this.codeOptions = [];
        }
        if (event.key === "Enter" && this.codeOptions.length === 1) {
            // Quick auto-select if only one result
            const only = this.codeOptions[0];
            this.valuesByKey = {
                ...this.valuesByKey,
                diagnosisCodeId: only.value,
                diagnosisSearch: only.label
            };
            this.codeOptions = [];
        }
    };



searchIcd9Debounced = this.debounce(async (term) => {
    try {
        const opts = await searchIcdCodes({
            term,
            icdType: 'ICD 9'
        });

        this.icd9Options = opts || [];
        console.log('icd9Options',this.icd9Options);
    } catch (e) {
        console.warn('ICD 9 search failed', e);
        this.icd9Options = [];
    }
}, 250);

searchIcd10Debounced = this.debounce(async (term) => {
    try {
        const opts = await searchIcdCodes({
            term,
            icdType: 'ICD 10'
        });

        this.icd10Options = opts || [];
        console.log('icd10Options',this.icd10Options);
    } catch (e) {
        console.warn('ICD 10 search failed', e);
        this.icd10Options = [];
    }
}, 250);

handleIcd9Typing = (event) => {
    const typed = (event.target.value || '').trim();
    this.icd9SearchText = typed;
    console.log('icd9SearchText',this.icd9SearchText );

    if (typed.length >= 2) {
        this.searchIcd9Debounced(typed);
    } else {
        this.icd9Options = [];
    }
};

handleIcd10Typing = (event) => {
    const typed = (event.target.value || '').trim();
    this.icd10SearchText = typed;
    console.log('icd10SearchText',this.icd10SearchText);
    if (typed.length >= 2) {
        this.searchIcd10Debounced(typed);
    } else {
        this.icd10Options = [];
    }

};

handleSelectIcd9 = (event) => {
    const id = event.currentTarget.dataset.id;
    const label = event.currentTarget.dataset.label;

    // Update visible text in the input
    this.icd9SearchText = label;
    // Close dropdown
    this.icd9Options = [];

    // Just store the selected ICD-9 in memory
    this.currentIcd9Id = id;

    // Optional: pequeño mensaje, pero aclarando que se guarda al generar
    this.showToast('Info', 'ICD-9 selected. It will be saved when you click Generate.', 'info');
};

handleSelectIcd10 = (event) => {
    const id = event.currentTarget.dataset.id;
    const label = event.currentTarget.dataset.label;

    this.icd10SearchText = label;
    this.icd10Options = [];

    this.currentIcd10Id = id;

    this.showToast('Info', 'ICD-10 selected. It will be saved when you click Generate.', 'info');
};




}