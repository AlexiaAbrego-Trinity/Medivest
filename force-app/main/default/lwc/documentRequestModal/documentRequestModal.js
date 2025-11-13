import { LightningElement, api, track, wire } from 'lwc';
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
import setCasePeriodDates from '@salesforce/apex/DocumentRequestController.setCasePeriodDates';
import setCaseAnnuity from '@salesforce/apex/DocumentRequestController.setCaseAnnuity';
import setCaseFundingChange from '@salesforce/apex/DocumentRequestController.setCaseFundingChange';
import fetchPayeeAddresses from '@salesforce/apex/DocumentRequestController.fetchPayeeAddresses';
import fetchAccountAddresses from '@salesforce/apex/DocumentRequestController.fetchAccountAddresses';
import setCaseAddress from '@salesforce/apex/DocumentRequestController.setCaseAddress';
import setCaseInsertInformation from '@salesforce/apex/DocumentRequestController.setCaseInsertInformation';
import searchCodes from '@salesforce/apex/DocumentRequestController.searchCodes';
import setCaseInjuredDiagnosis from '@salesforce/apex/DocumentRequestController.setCaseInjuredDiagnosis';
import setCaseWithdrawalExtras from '@salesforce/apex/DocumentRequestController.setCaseWithdrawalExtras';
import setSpecifyReason from '@salesforce/apex/DocumentRequestController.setSpecifyReason';
import setDocumentationRequest from '@salesforce/apex/DocumentRequestController.setDocumentationRequest';
import fetchExhaustionsForCase from '@salesforce/apex/DocumentRequestController.fetchExhaustionsForCase';
import setCaseExhaustion from '@salesforce/apex/DocumentRequestController.setCaseExhaustion';
import setCaseNextAnnuityDate from '@salesforce/apex/DocumentRequestController.setCaseNextAnnuityDate';
import validateBELAdmin from '@salesforce/apex/DocumentRequestController.validateBELAdmin';
import updateAdministrationAddress from '@salesforce/apex/DocumentRequestController.updateAdministrationAddress';
import getStateCodeToLabelMap from '@salesforce/apex/DocumentRequestController.getStateCodeToLabelMap';
// 1) UI API for dependent picklists
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import ACCOUNT_OBJECT from '@salesforce/schema/Account';

// 2) Countries from org (code->label)
import getCountryCodeToLabelMap from '@salesforce/apex/CountryStateService.getCountryCodeToLabelMap';
import setCaseLRDates from '@salesforce/apex/DocumentRequestController.setCaseLRDates';










export default class DocumentRequestModal extends NavigationMixin(LightningElement) {
  @api recordId;

  // Component version for debugging
  VERSION = "v2.2.3";

  // UI state
  @track step = 1;
  @track headerSubtitle = "Pick a department or search directly";
  @track addressOptions = []; // [{label, value}]
  @track adminBELValidation = null;
  @track adminId = null;

  // --- Dependent picklists (Country/State) ---
  @track countryOptions = []; // [{label, value}]
  @track stateOptions = [];   // [{label, value}]
  recordTypeId;               // UI API default record type for Account
  _controllerMap = {};        // countryCode -> index used in validFor
  _stateAllValues = [];       // all state values with .validFor metadata

  // DOC_RULES - Complete JavaScript array with all 10 rules
  // CRITICAL: More specific patterns MUST come before general patterns!
  DOC_RULES = [
    // 1. Email Template - Revision - WC - Southern California Edison (MUST COME FIRST!)
    {
      match: "email template - revision - wc - southern california edison",
      targetFieldApi: "trm_Edison_Template__c",
      checkboxFieldApi: "trm_Edison_Checkbox__c",
      baseLines: [
        "Revised Medicare Set-Aside Cost Driver Analysis Report",
        "Revised Medicare Set-Aside Allocation",
      ],
      options: [
        {
          key: "add-nq",
          label: 'Add "Revised Non-Qualified Medical Expense Cost Projection"',
          lines: ["Revised Non-Qualified Medical Expense Cost Projection"],
          affectsCheckbox: true,
        },
      ],
    },
    // 2. Email Template - Revision - WC (MUST COME AFTER Edison rule!)
    {
      match: "email template - revision - wc",
      targetFieldApi: "trm_WC_Template__c",
      checkboxFieldApi: "trm_WC_Checkbox__c",
      baseLines: [
        "Revised Medicare Set-Aside Cost Driver Analysis Report",
        "Revised Medicare Set-Aside Allocation",
        "Professional Administration Services Flyer",
      ],
      options: [
        {
          key: "add-rev-nq",
          label: 'Add "Revised Non-Qualified Medical Expense Cost Projection"',
          lines: ["Revised Non-Qualified Medical Expense Cost Projection"],
          affectsCheckbox: true,
        },
      ],
    },
    // 3. Email Template - Revision - Liability
    {
      match: "email template - revision - liability",
      targetFieldApi: "Email_Template_Liability__c",
      baseLines: [
        "Revised Medicare Set-Aside Cost Driver Analysis Report",
        "Revised Medicare Set-Aside Allocation Report",
        "Professional Administration Services Flyer",
      ],
      options: [
        {
          key: "add-nq-report",
          label: 'Add "Revised Non-Qualified Medical Expenses Report"',
          lines: ["Revised Non-Qualified Medical Expenses Report"],
        },
        {
          key: "add-apportionment",
          label: 'Add "Revised Medicare Set-Aside Apportionment Letter"',
          lines: ["Revised Medicare Set-Aside Apportionment Letter"],
        },
      ],
    },
    // 4. Recommendation - MSA - Prof Admin - Liability - To ATTD
    {
      match: "recommendation - msa - prof admin - liability - to attd",
      targetFieldApi: "trm_Profesional_Admin_Template__c",
      checkboxFieldApi: "trm_Profesional_Admin_Checkbox__c",
      baseLines: [
        "Medicare Set-Aside Cost Driver Analysis Report",
        "Medicare Set-Aside Allocation",
        "Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language",
        "Professional Administration Services Flyer",
      ],
      options: [
        {
          key: "add-nq",
          label: 'Add "Non-Qualified Medical Expense Cost Projection"',
          lines: ["Non-Qualified Medical Expense Cost Projection"],
          affectsCheckbox: true,
        },
      ],
    },
    // 5. Recommendation - MSA - Prof Admin - Liability - No Apportionment
    {
      match: "recommendation - msa - prof admin - liability - no apportionment",
      targetFieldApi: "trm_Profesional_Admin_Template__c",
      checkboxFieldApi: "trm_Profesional_Admin_Checkbox__c",
      baseLines: [
        "Medicare Set-Aside Cost Driver Analysis Report",
        "Medicare Set-Aside Allocation",
        "Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language",
        "Professional Administration Services Flyer",
      ],
      options: [
        {
          key: "add-nq",
          label: 'Add "Non-Qualified Medical Expense Cost Projection"',
          lines: ["Non-Qualified Medical Expense Cost Projection"],
          affectsCheckbox: true,
        },
      ],
    },
    // 6. Recommendation Package - MSA Recommendation Letter - Professional Admin - WC
    {
      match:
        "recommendation package - msa recommendation letter - professional admin - wc",
      targetFieldApi: "trm_Profesional_Admin_Template__c",
      checkboxFieldApi: "trm_Profesional_Admin_Checkbox__c",
      baseLines: [
        "Medicare Set-Aside Cost Driver Analysis Report",
        "Medicare Set-Aside Allocation",
        "Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language",
        "Professional Administration Services Flyer",
      ],
      options: [
        {
          key: "add-nq",
          label: 'Add "Non-Qualified Medical Expense Cost Projection"',
          lines: ["Non-Qualified Medical Expense Cost Projection"],
          affectsCheckbox: true,
        },
      ],
    },
    // 7. Recommendation - MSA - Self Admin - Liability
    {
      match: "recommendation - msa - self admin - liability",
      targetFieldApi: "trm_Self_Admin_Template__c",
      checkboxFieldApi: "trm_Self_Admin_Checkbox__c",
      baseLines: [
        "Medivest Invoice for Medicare Set-Aside Allocation",
        "Medicare Set-Aside Allocation",
        "Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language",
        "Self-Administration Kit Fee Quote",
      ],
      options: [
        {
          key: "add-nq",
          label: 'Add "Non-Qualified Medical Expense Cost Projection"',
          lines: ["Non-Qualified Medical Expense Cost Projection"],
          affectsCheckbox: true,
        },
      ],
    },
    // 8. Recommendation - MSA - Self Admin - WC
    {
      match: "recommendation - msa - self admin - wc",
      targetFieldApi: "trm_Self_Admin_Template__c",
      checkboxFieldApi: "trm_Self_Admin_Checkbox__c",
      baseLines: [
        "Medivest Invoice for Medicare Set-Aside Allocation",
        "Medicare Set-Aside Allocation",
        "Letter Outlining Medicare Eligibility Status and Referencing Sample Settlement Language",
        "Self-Administration Kit Fee Quote",
      ],
      options: [
        {
          key: "add-nq",
          label: 'Add "Non-Qualified Medical Expense Cost Projection"',
          lines: ["Non-Qualified Medical Expense Cost Projection"],
          affectsCheckbox: true,
        },
      ],
    },
    // 9. Recommendation Package - Revision - Liability - With Apportionment
    {
      match:
        "recommendation package - revision - liability - with apportionment",
      targetFieldApi: "trm_Apportionment_Template__c",
      baseLines: [
        "Revised Medicare Set-Aside Cost Driver Analysis Report",
        "Revised Medicare Set-Aside Allocation Report",
        "Revised Medicare Set-Aside Apportionment Letter",
        "Professional Administration Services Flyer",
      ],
      options: [
        {
          key: "add-rev-nq-report",
          label: 'Add "Revised Non-Qualified Medical Expenses Report"',
          lines: ["Revised Non-Qualified Medical Expenses Report"],
        },
      ],
    },
    // 10. Recommendation Package - Revision - Liability - No Apportionment (UPDATED per Ray's feedback)
    {
      match: "recommendation package - revision - liability - no apportionment",
      targetFieldApi: "trm_No_Apportionment_Template__c",
      checkboxFieldApi: "trm_No_Apportionment_Checkbox__c",
      baseLines: [
        "Revised Medicare Set-Aside Cost Driver Analysis Report",
        "Revised Medicare Set-Aside Allocation Report",
        "Professional Administration Services Flyer",
      ],
      options: [
        {
          key: "add-rev-nq-report",
          label: 'Add "Revised Non-Qualified Medical Expenses Report"',
          lines: ["Revised Non-Qualified Medical Expenses Report"],
          affectsCheckbox: true,
        },
      ],
    },
    // 11. Attestation
    {
      match: "attestation",
      //targetFieldApi: 'trm_Attestation_Template__c',
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "dateStart",
          label: "Date Period 1",
          type: "date",
          required: true,
        },
        {
          key: "dateEnd",
          label: "Date Period 2",
          type: "date",
          required: true,
        },
      ],
    },
    // 12. Temp Exhaustion MCA
    {
      match: "temp exhaustion mca",
      //targetFieldApi: '',
      baseLines: [],
      options: [],
      inputs: [
        { key: "annuity", label: "Annuity", type: "currency", required: true },
        {
          key: "exhaustionId",
          label: "Next Annuity Date",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    // 13. Cover Letter - CMS Submission - Funding Change Letter
    {
      match: "cover letter - cms submission - funding change letter",
      //targetFieldApi: '',
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "fundingChange",
          label: "Funding Change",
          type: "picklist",
          required: true,
          values: [
            {
              value: "changed from Lump Sum to Structured Annuity",
              label: "Changed from Lump Sum to Structured Annuity",
            },
            {
              value: "changed from Structured Annuity to Lump Sum",
              label: "Changed from Structured Annuity to Lump Sum",
            },
          ],
        },
      ],
    },
    //14. Cover Letter - CMS Submission - Re-Review Request
    {
      match: "cover letter - cms submission - re-review request",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
        {
          key: "insertInformation",
          label: "Insert Information",
          type: "text",
          required: true,
        },
      ],
    },
    //15.- Cover Letter - CMS Submission - Submitter Letter
    {
      match: "cover letter - cms submission - submitter letter",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
        {
          key: "diagnosisCodeId",
          label: "Diagnosis Code (select one)",
          type: "lookup",
          required: true,
        },
      ],
    },
    //16.- Cover Letter - CMS Submission - Withdrawal of Submission
    {
      match: "cover letter - cms submission - withdrawal of submission",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
        {
          key: "carrierOrInsurance",
          label: "Carrier or Insurance",
          type: "text",
          required: true,
        },
        {
          key: "allocationCompany",
          label: "Allocation Company",
          type: "text",
          required: true,
        },
      ],
    },
    // 17.- Email Template - CMS Approval - Counter Higher or Lower
    {
      match: "email template - cms approval - counter higher or lower",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "specifyReason",
          label: "Specify Reason",
          type: "text",
          required: true,
        },
      ],
    },
    // 18.- Email Template - CMS Submission - Additional Items Needed
    {
      match: "email template - cms submission - additional items needed",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "documentationRequest",
          label: "Documentation Request",
          type: "text",
          required: true,
        },
      ],
    },
    // 19.- MR Request
    {
      match: "mr request",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    // 20.- No Account Activity - Unable to Reach - Case
    {
      match: "no account activity - unable to reach",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    // 21.- Overpayment Inquiry Response Letter - Case
    {
      match: "overpayment inquiry response letter - case",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    // 22.- Provider Refund Check Denial - Case
    {
      match: "provider refund check denial - case",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    //23.-Unable to Reach - Welcome Call
    {
      match: "unable to reach - welcome call",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    //24. Refund Request
    {
      match: "refund request",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    //25. Temporary Exhaustion Letter: MSA - MSPRC-NGHP - Case
    {
      match: "temporary exhaustion letter: msa - msprc-nghp - case",
      baseLines: [],
      options: [],
      inputs: [
        { key: "nextAnnuityDate", label: "Next Annuity", type: "Date", required: true },
      ],
    },
    //26. Welcome Letter - MCA - Case
    {
      match: "welcome letter - mca - case",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    //27 .cms submission - cover letter - finding change request letter from the claimant
    {
      match: "cms submission - cover letter - finding change request letter from the claimant",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
      ],
    },
    //28 BEL - WCMSA - Case 
    //This document doesn't have any special rule, just want to validate the Administration Related record
    //have a valid Address before save
    {
      match: "bel - wcmsa - case",
      baseLines: [],
      options: [],
      inputs: [],
    },
    //30 CRC Letter Initial Appeal Dispute
    {
      match: "crc letter initial appeal dispute",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
        { key: "dateIssued", 
          label: "Select Date of the Medicare/CRC", 
          type: "date", 
          required: true 
        },
      ],
    },
    {
      match: "crc letter level 1 appeal redetermination",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
        { key: "dateIssued", 
          label: "Select date of Medicare/CRC demand letter", 
          type: "date", 
          required: true 
        },
        { key: "datePriorIssued", 
          label: "Select date of prior appeal/dispute", 
          type: "date", 
          required: true 
        },
      ],
    },
        {
      match: "crc letter level 2 appeal reconsideration",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
        { 
          key: "dateIssued", 
          label: "Select date of the Medicare/CRCr", 
          type: "date", 
          required: true 
        },
      ],
    },
      {
      match: "bcrc letter level 1 appeal redetermination",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
        { 
          key: "dateIssued", 
          label: "Select date of Medicare/CRC demand letter", 
          type: "date", 
          required: true 
        },
        { 
          key: "datePriorIssued", 
          label: "Select date of prior appeal/dispute", 
          type: "date", 
          required: true 
        },
      ],
    },
    {
      match: "bcrc letter initial appeal dispute",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "addressToUse",
          label: "Address",
          type: "picklist",
          required: true,
          values: [],
        },
        { key: "dateIssued", 
          label: "Select date of Medicare/CRC demand letter", 
          type: "date", 
          required: true 
        },
      ],
    },
    // Prior auth not required
    // Similar to BEL - WCMSA - Case 
    // validate the Administration Related record
    // have a valid Address before save
    {
      match: "prior auth not required",
      baseLines: [],
      options: [],
      inputs: [
        {
          key: "providerAttention",
          label: "Provider Attention",
          type: "text",
          required: true,
        }
      ],
    },
  ];

  // JavaScript DOC_RULES helper methods
  normalizeTemplateName(templateName) {
    if (!templateName) return "";
    return templateName.toLowerCase().trim().replace(/\s+/g, " "); // Multiple spaces → single space
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
    if (!rule) return "";

    // SIMPLE FIX: Separate "Professional Administration Services Flyer" from other lines
    const flyerLines = rule.baseLines.filter((line) =>
      line.includes("Professional Administration Services Flyer")
    );
    const nonFlyerLines = rule.baseLines.filter(
      (line) => !line.includes("Professional Administration Services Flyer")
    );

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

    return allLines.join("\n");
  }

  @track searchTerm = "";
  @track loading = false;
  @track loadingMessage = "Generating...";

  // data
  @track departments = []; // [{label,value,className}]
  @track subDepartments = []; // idem
  @track templates = []; // [{id,name,className}]

  // selections
  @track selectedDepartment;
  @track selectedSubDepartment;
  @track selectedTemplateId;
  @track selectedTemplateName;

  // step4
  @track optionalContent = "";

  // DOC_RULES advanced document properties
  @track selectedOptions = [];
  @track isAdvancedDocument = false;
  @track detailsTextHtml = "";
  @track detailsOptions = [];
  @track currentRule = null; // Store current DOC_RULE for generation
  @track currentInputs = [];
  @track valuesByKey = {};
  @track codeOptions = []; // Dinamic options to lookup codes. opciones dinámicas del lookup de códigos
  _codeSearchDebounce; // debounce handler para

  // stepper classes (precalculadas — nada de llamadas en template)
  get step1Class() {
    return "step " + (this.step >= 1 ? "active" : "");
  }
  get step2Class() {
    return "step " + (this.step >= 2 ? "active" : "");
  }
  get step3Class() {
    return "step " + (this.step >= 3 ? "active" : "");
  }
  get step4Class() {
    return "step " + (this.step >= 4 ? "active" : "");
  }

  // visibility
  get showStep1() {
    return this.step === 1;
  }
  get showStep2() {
    return this.step === 2;
  }
  get showStep3() {
    return this.step === 3;
  }
  get showStep4() {
    return this.step === 4;
  }

  get hasDepartments() {
    return this.departments && this.departments.length > 0;
  }
  get hasSubDepartments() {
    return this.subDepartments && this.subDepartments.length > 0;
  }
  get hasTemplates() {
    return this.templates && this.templates.length > 0;
  }

  @wire(getObjectInfo, { objectApiName: ACCOUNT_OBJECT })
  wiredAccountInfo({ data }) {
    // Get Account default record type to resolve picklist metadata
    if (data) {
      this.recordTypeId = data.defaultRecordTypeId;
    }
  }

    // Load dependent picklist metadata via wire (required; wire-only adapter)
  // This caches controllerValues and all state values (with validFor) for Account.BillingStateCode
  @wire(getPicklistValuesByRecordType, { objectApiName: ACCOUNT_OBJECT, recordTypeId: '$recordTypeId' })
  wiredPicklists({ data, error }) {
    if (data) {
      const pv = data.picklistFieldValues;
      // controllerValues maps each countryCode to an index used by validFor arrays
      this._controllerMap  = pv?.BillingStateCode?.controllerValues || {};
      // values is the full list of state options with their validFor indices
      this._stateAllValues = pv?.BillingStateCode?.values || [];
    } else if (error) {
      // If wire fails, we leave arrays empty (stateOptions will be blank)
      this._controllerMap  = {};
      this._stateAllValues = [];
      // (Optional) you could log error
      // console.warn('wiredPicklists error', JSON.stringify(error));
    }
  }


    // Load country picklist (code->label) once from Apex global catalog
  async loadCountryOptionsOnce() {
    if (this.countryOptions.length) return; // already loaded
    const map = await getCountryCodeToLabelMap();
    this.countryOptions = Object.keys(map).map(code => ({ value: code, label: map[code] }));
  }

  /*handleDynamicInputChange = (e) => {
    const key = e.target.dataset.key;
    const val =
      e.detail && e.detail.value !== undefined
        ? e.detail.value
        : e.target.value;

    this.valuesByKey = { ...this.valuesByKey, [key]: val || null };
  };*/
  handleDynamicInputChange = async (e) => {
    const key = e.target.dataset.key;
    const val = (e.detail && e.detail.value !== undefined) ? e.detail.value : e.target.value;

    if (key === 'countryCode') {
      // When country changes, reset state and reload dependent options
      this.valuesByKey = { ...(this.valuesByKey || {}), countryCode: val || null, state: null };
      await this.loadStateOptions(val);
    } else {
      this.valuesByKey = { ...(this.valuesByKey || {}), [key]: val || null };
    }

    // Basic inline validation feedback on the input itself
    const cmp = e.target;
    if (['street','city','postalCode','countryCode','state'].includes(key)) {
      if (!val) {
        cmp.setCustomValidity('This field is required');
      } else if (key === 'state' && !this.valuesByKey?.countryCode) {
        cmp.setCustomValidity('Select country first');
      } else {
        cmp.setCustomValidity('');
      }
      cmp.reportValidity();
    }
  };


  /*
  get disableGenerate() {
    // no inputs for this template? no blocker
    if (!this.currentInputs?.length) return false;

    //  Si es BEL, debe pasar validación de address
    if (this.currentRule?.match === 'bel - wcmsa - case' && !this.isBelAddressValid()) {
      return true;
    }

    // There is missing inputs?
    const missing = this.currentInputs.some(
      (i) => i.required && !this.valuesByKey?.[i.key]
    );

    // Bussines rule: DateEnd >= DateStart
    const s = this.valuesByKey?.dateStart;
    const e = this.valuesByKey?.dateEnd;
    if (s && e && e < s) return true;

    return missing;
  }*/
  // Use inside your existing disableGenerate getter:
  get disableGenerate() {
    // Block Generate if BEL requires address completion and something is missing
    if ((this.currentRule?.match === 'bel - wcmsa - case' || this.currentRule?.match === 'prior auth not required') && !this.isBelAddressValid()) return true;

    // Keep your existing required-input checks (dates, other templates, etc.)
    if (!this.currentInputs?.length) return false;
    const missing = this.currentInputs.some(i => i.required && !this.valuesByKey?.[i.key]);
    const s = this.valuesByKey?.dateStart;
    const e = this.valuesByKey?.dateEnd;
    if (s && e && e < s) return true;

    return missing;
  }

  get isGenerateDisabled() {
    return this.loading || this.disableGenerate;
  }

  get hasDynamicInputs() {
    return Array.isArray(this.currentInputs) && this.currentInputs.length > 0;
  }

  get inputsWithValues() {
    const src = this.currentInputs || [];
    const map = this.valuesByKey || {};
    const currencyCode = "USD";

    return src.map((inp) => {
      const base = {
        ...inp,
        value: map[inp.key] ?? null,
        _renderType: inp.type,
        _formatter: null,
        _currencyCode: null,
        _step: null,
        _isCombo: false,
        _options: null,
        _placeholder: null,
        _isLookup: inp.type === "lookup",
        _isPicklist: inp.type === "picklist",
      };

      if (inp.type === "currency") {
        base._renderType = "number";
        base._formatter = "currency";
        base._currencyCode = currencyCode;
        base._step = "0.01";
      }

      if (inp.type === "picklist") {
        base._isCombo = true;
        base._options = Array.isArray(inp.values) ? inp.values : [];
      }

      // NUEVO: lookup para Diagnosis Code
      if (inp.type === "lookup") {
        // NO usar el combobox genérico
        base._isCombo = false;

        // marcar que es lookup
        base._isLookup = true;

        // placeholder del input de búsqueda
        base._placeholder = "Type to search codes...";

        // texto visible en el search (lo guardamos en valuesByKey.diagnosisSearch)
        base.displayValue = map.diagnosisSearch || "";
      }

      return base;
    });
  }

  get adminBELBlockReason() {
    // Only applies to the BEL rule
    if (!this.currentRule || (this.currentRule.match !== 'bel - wcmsa - case' || this.currentRule?.match === 'prior auth not required')) return null;
    const v = this.adminBELValidation;
    if (!v) return 'Validating Administration address...';
    if (!v.hasAdministration) return 'This Document has no Administration related. Please relate an Administration record on the Case.';
    if (!v.hasFullAddress) return `The related Administration is missing address fields: ${ (v.missingFields || []).join(', ') }. Please complete the address on the Administration record.`;
    return null; // ok to proceed
  }

  get showBelAddressInputs() {
    return (this.currentRule?.match === 'bel - wcmsa - case' || this.currentRule?.match === 'prior auth not required')
      && this.adminBELValidation?.hasAdministration
      && !this.adminBELValidation?.hasFullAddress;
  }
  
  connectedCallback() {
    console.log(
      "[DocumentRequestModal] Component initialized - Version:",
      this.VERSION
    );
    this.loadDepartments();
  }

  // -------- Search ----------
  onSearchInput = (e) => {
    this.searchTerm = e.target.value;
  };
  onSearchKeydown = (e) => {
    if (e.key === "Enter") this.doSearch();
  };
  async doSearch() {
    const term = (this.searchTerm || "").trim();

    // Validate search term is not empty
    if (!term) {
      this.showToast(
        "Search Required",
        "Please enter a search term",
        "warning"
      );
      return;
    }

    const rows = await searchMappingsByName({ term });

    this.templates = (rows || []).map((r) => ({
      id: r.Id,
      name: r.Name,
      className: "pill",
    }));

    // Only advance to step 3 if results found
    if (this.templates.length > 0) {
      this.step = 3;
      this.headerSubtitle = `Search results for "${term}"`;
    } else {
      // Stay on current step and show clear message
      this.showToast(
        "No Results",
        `No documents found matching "${term}"`,
        "info"
      );
      this.step = 1;
      this.headerSubtitle =
        "No results found - try another search or browse by category";
    }

    // Clear search field after search execution
    this.searchTerm = "";
    // Clear previous selection
    this.selectedTemplateId = undefined;
    this.selectedTemplateName = undefined;
    this.markSelectedInArray(this.templates, "id", this.selectedTemplateId);
  }

  // -------- Step 1 ----------
  async loadDepartments() {
    const rows = await fetchDepartments();
    this.departments = (rows || []).map((r) => ({
      label: r,
      value: r,
      className: "pill",
    }));
    this.step = 1;
    this.headerSubtitle = "Pick a department or use search";
  }
  pickDepartment = (e) => {
    const val = e.currentTarget.dataset.value;
    this.selectedDepartment = val;
    this.markSelectedInArray(this.departments, "value", val);
    this.searchTerm = "";
    this.loadSubDepartments(val);
  };

  // -------- Step 2 ----------
  async loadSubDepartments(dept) {
    // Use filtered method to get only sub-departments with documents in this department
    const rows = await fetchSubDepartmentsByDepartment({ department: dept });
    const subDepts = (rows || []).map((r) => ({
      label: r,
      value: r,
      className: "pill",
    }));
    // Add "All" option at the beginning
    this.subDepartments = [
      { label: "All", value: "All", className: "pill" },
      ...subDepts,
    ];
    // Siempre mostramos paso 2; si sólo está 'All', el usuario puede saltar.
    this.step = 2;
    this.headerSubtitle = `Department: ${dept}`;
  }
  pickSubDepartment = async (e) => {
    const val = e.currentTarget.dataset.value;
    this.selectedSubDepartment = val;
    this.markSelectedInArray(this.subDepartments, "value", val);
    this.searchTerm = "";
    await this.loadTemplates();
  };

  // -------- Step 3 ----------
  async loadTemplates() {
    const dept = this.selectedDepartment;
    const sub = this.selectedSubDepartment;

    // Use production fetchDocumentsUnified method
    const departmentInputs = [dept];
    const subDepartmentNames = sub && sub !== "All" ? [sub] : ["All"];

    const result = await fetchDocumentsUnified({
      departmentInputs: departmentInputs,
      subDepartmentNames: subDepartmentNames,
    });

    this.templates = (result.rows || []).map((r) => ({
      id: r.Id,
      name: r.Name,
      className: "pill",
    }));
    this.step = 3;
    this.headerSubtitle = `Department: ${dept}${
      sub && sub !== "All" ? " / " + sub : ""
    }`;
    // limpiar selección visual
    this.selectedTemplateId = undefined;
    this.selectedTemplateName = undefined;
    this.markSelectedInArray(this.templates, "id", this.selectedTemplateId);
  }


  pickTemplate = async (e) => {
    const id = e.currentTarget.dataset.id;
    this.selectedTemplateId = id;
    this.markSelectedInArray(this.templates, "id", id);

    const template = this.templates.find((t) => t.id === id);
    this.selectedTemplateName = template ? template.name : "";

    // reset
    this.resetAdvancedDocumentState();

    const rule = this.findMatchingRule(this.selectedTemplateName);
    if (rule) {
      this.isAdvancedDocument = true;
      this.detailsTextHtml = this.generateTemplateContent(rule, []).replace(
        /\n/g,
        "<br>"
      );
      this.detailsOptions = rule.options || [];
      this.currentRule = rule;

      // Base inputs desde DOC_RULES
      this.currentInputs = Array.isArray(rule.inputs) ? [...rule.inputs] : [];

      // 2.a) load address
      if (
        this.isCase &&
        (rule.match ===
          "cover letter - cms submission - funding change letter" ||
          rule.match === "cover letter - cms submission - re-review request" ||
          rule.match === "cover letter - cms submission - submitter letter" ||
          rule.match ===
            "cover letter - cms submission - withdrawal of submission" ||
          rule.match === "mr request" ||
          rule.match === "overpayment inquiry response letter - case" ||
          rule.match === "provider refund check denial - case")
      ) {
        try {
          console.log("Payee addres");
          const opts = await fetchPayeeAddresses({ caseId: this.recordId });
          this.addressOptions = (opts || []).map((o) => ({
            label: o.label,
            value: o.value,
          }));
          // if DOC_RULES, agrégalo; si existe, solo inyecta options
          const idx = this.currentInputs.findIndex(
            (i) => i.key === "addressToUse"
          );
          if (idx >= 0) {
            this.currentInputs[idx] = {
              ...this.currentInputs[idx],
              values: this.addressOptions,
              required: true,
              type: "picklist",
            };
          } else if (this.addressOptions.length > 0) {
            this.currentInputs.push({
              key: "addressToUse",
              label: "Address",
              type: "picklist",
              required: true,
              values: this.addressOptions,
            });
          }
        } catch (err) {
          console.warn("Failed to fetch payee addresses:", err);
          this.addressOptions = [];
        }
      } else if (
        this.isCase &&
        (rule.match === "no account activity - unable to reach" ||
          rule.match === "unable to reach - welcome call" ||
          rule.match === "refund request" ||
          rule.match === "welcome letter - mca - case" ||
          rule.match ===
            "cms submission - cover letter - finding change request letter from the claimant" ||
          rule.match === "bel - lmsa - case" ||
          rule.match === "crc letter initial appeal dispute" ||
          rule.match === "crc letter level 1 appeal redetermination" ||
          rule.match === "crc letter level 2 appeal reconsideration" ||
          rule.match === "bcrc letter level 1 appeal redetermination" ||
          rule.match === "bcrc letter initial appeal dispute")
      ) {
        try {
          console.log("Account address");
          const opts = await fetchAccountAddresses({ caseId: this.recordId });
          this.addressOptions = (opts || []).map((o) => ({
            label: o.label,
            value: o.value,
          }));
          //
          const idx = this.currentInputs.findIndex(
            (i) => i.key === "addressToUse"
          );
          if (idx >= 0) {
            this.currentInputs[idx] = {
              ...this.currentInputs[idx],
              values: this.addressOptions,
              required: true,
              type: "picklist",
            };
          } else if (this.addressOptions.length > 0) {
            this.currentInputs.push({
              key: "addressToUse",
              label: "Address",
              type: "picklist",
              required: true,
              values: this.addressOptions,
            });
          }
        } catch (err) {
          console.warn("Failed to fetch Account (Entity) addresses:", err);
          this.addressOptions = [];
        }
      }

      // -- Temp Exhaustion MCA: load Exhaustion picklist tied to Case's Member Account (Custodial_Account__c)
      if (this.isCase && rule.match === "temp exhaustion mca") {
        try {
          const data = await fetchExhaustionsForCase({ caseId: this.recordId });
          const opts = data && Array.isArray(data.options) ? data.options : [];
          const recommended = data ? data.recommendedId : null;

          const idx = this.currentInputs.findIndex(
            (i) => i.key === "exhaustionId"
          );
          if (idx >= 0) {
            this.currentInputs[idx] = {
              ...this.currentInputs[idx],
              type: "picklist",
              values: opts,
              required: true,
            };
          }

          // Preselect recommended option in the component state
          if (recommended) {
            this.valuesByKey = {
              ...this.valuesByKey,
              exhaustionId: recommended,
            };
          }
        } catch (err) {
          console.warn(
            "Failed to fetch Exhaustions for Temp Exhaustion MCA:",
            err
          );
        }
      }

      /* 2.b) Submitter Letter → llenar options del picklist address definido en DOC_RULES
      if (
        rule.match === "cover letter - cms submission - submitter letter" &&
        this.isCase
      ) {
        try {
          const opts = await fetchPayeeAddresses({ caseId: this.recordId });
          this.addressOptions = (opts || []).map((o) => ({
            label: o.label,
            value: o.value,
          }));
          const idx = this.currentInputs.findIndex(
            (i) => i.key === "addressToUse"
          );
          if (idx >= 0) {
            this.currentInputs[idx] = {
              ...this.currentInputs[idx],
              values: this.addressOptions,
            };
          }
        } catch (err) {
          console.warn("Failed to fetch payee addresses (submitter):", err);
          this.addressOptions = [];
        }
      }*/

      if ((rule.match === "bel - wcmsa - case" || this.currentRule?.match === 'prior auth not required') && this.isCase) {
        try {
          // 1) Validar en Apex si hay Administration y si tiene dirección completa
          const v = await validateBELAdmin({ caseId: this.recordId });
          this.adminBELValidation = v || null;
          this.adminId = v?.administrationId || null;

          // 2) Si NO hay Administration, avisa y bloquea Generate (sin inputs)
          if (!v?.hasAdministration) {
            this.showToast(
              "Administration required",
              "Please relate an Administration record on the Case before generating this document.",
              "error"
            );
            // No agregamos inputs aquí; disableGenerate quedará true por isBelAddressValid()
            // y el usuario verá el toast.
            // Seguimos mostrando Step 4 con el detalle del template.
          } else if (v?.hasAdministration && !v?.hasFullAddress) {
            // 3) Si hay Administration pero faltan campos, mostramos inputs de Address

            // Cargar países de org (code->label) una vez
            await this.loadCountryOptionsOnce();

            // Prefijar Country por defecto "US" si está vacío
            if (!this.valuesByKey?.countryCode) {
              this.valuesByKey = { ...(this.valuesByKey || {}), countryCode: "US", state: null };
            }

            // Cargar estados válidos para el país seleccionado
            await this.loadStateOptions(this.valuesByKey.countryCode);

            // 4) Inyectar inputs dinámicos requeridos (se agregan a currentInputs)
            //    NOTA: keys deben coincidir con tu handleDynamicInputChange (street, city, postalCode, countryCode, state)
            const addressInputs = [
              {
                key: "countryCode",
                label: "Country",
                type: "picklist",
                required: true,
                values: this.countryOptions // [{value,label}]
              },
              {
                key: "state",
                label: "State/Province",
                type: "picklist",
                required: true,
                values: this.stateOptions // filtrados por country
              },
              { key: "street", label: "Street", type: "text", required: true },
              { key: "city", label: "City", type: "text", required: true },
              { key: "postalCode", label: "Postal Code", type: "text", required: true }
            ];

            // Empuja después de los inputs base que ya cargaste del rule (en tu código ya hiciste: this.currentInputs = [...rule.inputs] )
            this.currentInputs = [...(this.currentInputs || []), ...addressInputs];
          }
        } catch (err) {
          console.warn("validateBELAdmin failed:", err);
          // En caso de error, bloquea para evitar generar sin validación
          this.adminBELValidation = null;
          this.adminId = null;
          this.showToast("Error", this.errMsg(err) || "Failed to validate Administration address.", "error");
        }
      }




      // reset values después de armar inputs
      //this.valuesByKey = {};
      if (rule.match !== "temp exhaustion mca" && rule.match !== "bel - wcmsa - case" && rule.match !== 'prior auth not required') {
        // For all other templates, keep the previous behavior
        this.valuesByKey = {};
      }
    }

    this.step = 4;
    this.headerSubtitle = `Document: ${this.selectedTemplateName}`;
    this.optionalContent = "";
  };

  // -------- Step 4 ----------
  onOptionalChange = (e) => {
    this.optionalContent = e.target.value;
  };
  goBackToDocs = () => {
    this.step = 3;
  };

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
      this.selectedOptions = this.selectedOptions.filter(
        (opt) => opt !== optionKey
      );
    }

    this.updateRichTextContent();
  };

  updateRichTextContent = () => {
    if (this.currentRule) {
      // Generate content using DOC_RULES structure
      const newContent = this.generateTemplateContent(
        this.currentRule,
        this.selectedOptions
      );
      this.detailsTextHtml = newContent.replace(/\n/g, "<br>");
    }
  };

  resetAdvancedDocumentState = () => {
    this.documentRuleInfo = null;
    this.selectedOptions = [];
    this.isAdvancedDocument = false;
    this.detailsTextHtml = "";
    this.detailsOptions = [];
    // clean dynamic inputs
    this.currentInputs = [];
    this.valuesByKey = {};
  };

  // -------- Navigation Methods - Clickable Stepper ----------
  goToStep1 = () => {
    if (this.step > 1) {
      this.step = 1;
      this.headerSubtitle = "Pick a department or search directly";
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
      this.searchTerm = "";
    }
  };

  goToStep3 = () => {
    if (
      this.step > 3 &&
      this.selectedDepartment &&
      this.selectedSubDepartment
    ) {
      this.step = 3;
      this.headerSubtitle = `Sub-Department: ${this.selectedSubDepartment}`;
      // Clear subsequent selections
      this.selectedTemplateId = undefined;
      this.selectedTemplateName = undefined;
      this.searchTerm = "";
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
    this.searchTerm = "";
    this.departments = [];
    this.subDepartments = [];
    this.templates = [];
    this.selectedDepartment = undefined;
    this.selectedSubDepartment = undefined;
    this.selectedTemplateId = undefined;
    this.selectedTemplateName = undefined;
    this.optionalContent = "";
    this.headerSubtitle = "Pick a department or search directly";
    this.loadDepartments();
  };
  // Quick Action context detection - defensive programming for different deployment contexts
  isQuickAction() {
    // Quick Actions run in modal context with specific URL patterns or iframe detection
    return (
      window.location.href.includes("modal") ||
      window.location.href.includes("action") ||
      window.parent !== window
    ); // iframe detection
  }

  handleExit = () => {
    // TRINITY FIX v3: Silent exit - no toasts, no navigation, just reset
    console.log("🎯 TRINITY EXIT v3: X button clicked - silent reset only");

    // Always just silently reset the component state - no navigation, no toasts
    this.selectedDepartments = [];
    this.selectedSubDepartments = [];
    this.selectedDocuments = [];
    this.currentStep = 1;
    this.searchTerm = "";
    this.searchResults = [];
    this.showSearchResults = false;
    this.isLoading = false;
    this.showAdditionalDetails = false;
    this.additionalDetails = {};
    this.error = null;

    console.log(
      "🎯 TRINITY EXIT v3: Component state reset complete - no toasts, no navigation"
    );
  };

  async generate() {
    console.log("Generate method called!"); // Debug log
    console.log("selectedTemplateId:", this.selectedTemplateId);
    console.log("recordId:", this.recordId);

    if (!this.selectedTemplateId || !this.recordId) {
      this.showToast(
        "Error",
        "Missing template or record information.",
        "error"
      );
      return;
    }

    try {
      // Smooth loading state transition
      this.loading = true;
      this.loadingMessage = "Preparing document...";

      // Small delay to ensure UI updates smoothly (eliminates flicker)
      await this.delay(100);

      console.log("Starting document generation...");
      console.log("Advanced document:", this.isAdvancedDocument);

      // STEP 1: ALWAYS populate agent fields (all objects)
      this.loadingMessage = "Updating agent information...";
      try {
        await updateAgentFields({ recordId: this.recordId });
        console.log("Agent fields updated successfully");
      } catch (agentError) {
        console.warn("Failed to update agent fields:", agentError);
        // Continue with generation even if agent field update fails
      }

      let docId;

      const objectApiName = this.getObjectApiName();
      console.log("OBJECT:", objectApiName);

      // STEP 2: Handle advanced documents (Case only)
      if (this.isAdvancedDocument && this.currentRule && this.isCase) {
        // Advanced document - update template fields then generate
        console.log("Using enhanced generation for advanced document");
        this.loadingMessage = "Processing advanced document rules...";

        // Generate template content using JavaScript DOC_RULES
        const templateContent = this.generateTemplateContent(
          this.currentRule,
          this.selectedOptions
        );

        // Determine checkbox value
        let checkboxValue = false;
        if (this.selectedOptions && this.selectedOptions.length > 0) {
          for (const option of this.currentRule.options) {
            if (
              this.selectedOptions.includes(option.key) &&
              option.affectsCheckbox
            ) {
              checkboxValue = true;
              break;
            }
          }
        }

        // 🚨 MATT'S DEBUG: Edison Template Field Population Before WebMerge
        const isEdisonTemplate =
          this.currentRule.targetFieldApi === "trm_Edison_Template__c";
        if (isEdisonTemplate) {
          console.log(
            "🔥 EDISON DEBUG: About to populate trm_Edison_Template__c field BEFORE webmerge"
          );
          console.log("📝 Edison Template Content Details:");
          console.log("  - Target Field: " + this.currentRule.targetFieldApi);
          console.log(
            "  - Content Length: " +
              (templateContent ? templateContent.length : 0) +
              " characters"
          );
          console.log(
            '  - Content Preview: "' +
              (templateContent
                ? templateContent.substring(0, 100) + "..."
                : "NULL") +
              '"'
          );
          console.log(
            "  - Checkbox Field: " + this.currentRule.checkboxFieldApi
          );
          console.log("  - Checkbox Value: " + checkboxValue);
          console.log(
            "🎯 EDISON DEBUG: This field MUST be populated BEFORE webmerge payload is sent"
          );
        }

        // Update case template fields before generation
        try {
          if (this.currentRule?.targetFieldApi) {
            console.log("💾 Calling updateCaseTemplateFields (guarded)...");
            await updateCaseTemplateFields({
              caseId: this.recordId,
              targetFieldApi: this.currentRule.targetFieldApi,
              value: templateContent,
              checkboxFieldApi: this.currentRule.checkboxFieldApi || null,
              checkboxValue: checkboxValue,
            });
            console.log("✅ Case template fields updated successfully");

            if (isEdisonTemplate) {
              console.log(
                "🎯 trm_Edison_Template__c populated and ready before merge"
              );
            }
          } else {
            console.log(
              "ℹ️ No targetFieldApi in rule — skipping updateCaseTemplateFields"
            );
          }
        } catch (fieldError) {
          console.warn(
            "❌ Failed to update Case template fields (guarded):",
            fieldError
          );
          if (isEdisonTemplate) {
            console.error(
              "🔥 CRITICAL: Edison template field population FAILED!"
            );
          }
          // Continue with generation even if field update fails
        }

        // === DATES: set Case period dates before merging (if present) ===
        if (this.currentInputs?.length) {
          if (this.isCase && this.currentRule?.match === "attestation") {
            const s = this.valuesByKey.dateStart || null;
            const e = this.valuesByKey.dateEnd || null;
            await setCasePeriodDates({
              caseId: this.recordId,
              dateStart: s,
              dateEnd: e,
            });
          }
        }

        // STEP 3: Generate document
        this.loadingMessage = "Generating document...";
        console.log(
          "🖥️ UI: About to call mergeWithMapping (production method)"
        );

        // 🚨 MATT'S DEBUG: Critical timing validation for Edison template
        if (isEdisonTemplate) {
          console.log(
            "🎯 EDISON DEBUG: ===== CRITICAL TIMING VALIDATION ====="
          );
          console.log(
            "🔥 EDISON DEBUG: trm_Edison_Template__c field has been populated"
          );
          console.log(
            "🚀 EDISON DEBUG: About to send webmerge payload - field MUST be populated now"
          );
          console.log(
            "📋 EDISON DEBUG: WebMerge will query Case record and should find populated field"
          );
          console.log("🎯 EDISON DEBUG: ===== END TIMING VALIDATION =====");
        }

        // 🚨 TRINITY WEBMERGE DEBUG: Log full object being sent to WebMerge
        const webmergePayload = {
          mappingId: this.selectedTemplateId,
          recordId: this.recordId,
          objectApiName: objectApiName,
        };
        console.log(
          "🚀 TRINITY WEBMERGE DEBUG: Full payload being sent to mergeWithMapping:"
        );
        console.log(
          "📦 Payload Object:",
          JSON.stringify(webmergePayload, null, 2)
        );
        console.log("🔍 Payload Details:");
        console.log(
          "  - mappingId (selectedTemplateId):",
          webmergePayload.mappingId
        );
        console.log("  - recordId:", webmergePayload.recordId);
        console.log("  - objectApiName:", webmergePayload.objectApiName);

        if (isEdisonTemplate) {
          console.log(
            "🔥 EDISON DEBUG: Sending webmerge payload NOW - Edison field should be populated"
          );
        }

        if (this.currentRule?.match === "temp exhaustion mca") {
          // 1) Persist Annuity (currency) into Case.trm_Annuity__c
          const raw = this.valuesByKey?.annuity;
          const amount = raw !== null && raw !== undefined ? Number(raw) : NaN;
          try {
            await setCaseAnnuity({
              caseId: this.recordId,
              annuity: isFinite(amount) ? amount : null,
            });
          } catch (e) {
            console.warn("Failed to set Case Annuity:", e);
          }

          // 2) Persist user-selected Exhaustion into Case.trm_Exhaustion__c
          const chosenExId = this.valuesByKey?.exhaustionId || null;
          try {
            await setCaseExhaustion({
              caseId: this.recordId,
              exhaustionId: chosenExId,
            });
          } catch (e) {
            console.warn("Failed to set Case.trm_Exhaustion__c:", e);
          }

          // Optional fallback (disabled by default):
          // If no selection, you could auto-map the closest active one:
          // if (!chosenExId) {
          //   try { await mapClosestActiveExhaustionToCase({ caseId: this.recordId }); } catch (e) { /* ignore */ }
          // }
        }

        const isFundingChangeDoc =
          this.currentRule?.match ===
          "cover letter - cms submission - funding change letter";
        if (isFundingChangeDoc && this.isCase) {
          const sel = this.valuesByKey?.fundingChange || null;
          try {
            // save Case.trm_Funding_Change__c
            await setCaseFundingChange({
              caseId: this.recordId,
              fundingChange: sel,
            });
          } catch (e) {
            console.warn("Failed to set Funding Change on Case:", e);
          }
        }

        // If this is the Funding Change Letter and user selected an address, persist it in Case.trm_Address__c
        if (
          (this.currentRule?.match ===
            "cover letter - cms submission - funding change letter" ||
            this.currentRule?.match ===
              "cover letter - cms submission - re-review request" ||
            this.currentRule?.match ===
              "no account activity - unable to reach" ||
            this.currentRule?.match === "mr request" ||
            this.currentRule?.match ===
              "provider refund check denial - case" || 
            this.currentRule?.match === 
            "cms submission - cover letter - finding change request letter from the claimant" ||
            this.currentRule?.match === 
            "refund request" || 
            this.currentRule?.match === "bel - lmsa - case") &&
          this.isCase
        ) {
          const selectedAddr = this.valuesByKey?.addressToUse || null;
          if (selectedAddr) {
            try {
              await setCaseAddress({
                caseId: this.recordId,
                address: selectedAddr,
              });
              console.log("Case.trm_Address__c updated with selected address");
            } catch (e) {
              console.warn("Failed to persist Case.trm_Address__c:", e);
              // Non-blocking: continue generation
            }
          }
        }

        // Save insert information
        if (
          this.isCase &&
          this.currentRule?.match ===
            "cover letter - cms submission - re-review request"
        ) {
          const info = this.valuesByKey?.insertInformation || null;
          try {
            await setCaseInsertInformation({
              caseId: this.recordId,
              insertInformation: info,
            });
            console.log(
              "Case.trm_Insert_Information__c updated with provided information"
            );
          } catch (e) {
            console.warn(
              "Failed to persist trm_Insert_Information__c on Case:",
              e
            );
            // Non-blocking: continue generation
          }
        }

        // --- Submitter Letter: save direcction + diagnosis code ---
        const isSubmitterLetter =
          this.currentRule?.match ===
          "cover letter - cms submission - submitter letter";
        if (isSubmitterLetter && this.isCase) {
          // 1) Address (setCaseAddress do it)
          const selectedAddr = this.valuesByKey?.addressToUse || null;
          if (selectedAddr) {
            try {
              await setCaseAddress({
                caseId: this.recordId,
                address: selectedAddr,
              });
            } catch (e) {
              console.warn("Failed to persist Case address fields", e);
            }
          }

          // 2) Diagnosis Code → lookup en Case.trm_Diagnosis_Code__c
          const codeId = this.valuesByKey?.diagnosisCodeId || null;
          if (codeId) {
            try {
              await setCaseInjuredDiagnosis({ caseId: this.recordId, codeId });
            } catch (e) {
              console.warn("Failed to set Diagnosis Code on Case", e);
            }
          }
        }

        // --- Withdrawal of Submission: persist address + carrier/insurance + allocation company ---
        const isWithdrawal =
          this.currentRule?.match ===
          "cover letter - cms submission - withdrawal of submission";
        if (isWithdrawal && this.isCase) {
          // 1) Address → use existing setCaseAddress helper
          const selectedAddr = this.valuesByKey?.addressToUse || null;
          if (selectedAddr) {
            try {
              await setCaseAddress({
                caseId: this.recordId,
                address: selectedAddr,
              });
            } catch (e) {
              console.warn(
                "Failed to persist Case address fields (withdrawal)",
                e
              );
            }
          }

          // 2) Carrier/Insurance + Allocation Company → save text to Case fields
          const carrierTxt = this.valuesByKey?.carrierOrInsurance || null;
          const companyTxt = this.valuesByKey?.allocationCompany || null;
          try {
            await setCaseWithdrawalExtras({
              caseId: this.recordId,
              carrierOrInsurance: carrierTxt,
              allocationCompany: companyTxt,
            });
          } catch (e) {
            console.warn("Failed to set Withdrawal extras on Case", e);
          }
        }

        // --- email template - cms approval - counter higher or lower
        const isCounterHigher =
          this.currentRule?.match ===
          "email template - cms approval - counter higher or lower";
        if (isCounterHigher && this.isCase) {
          // 1) specifyReason→ save text to Case fields
          const specifyReasonTxt = this.valuesByKey?.specifyReason || null;
          try {
            await setSpecifyReason({
              caseId: this.recordId,
              insertInformation: specifyReasonTxt,
            });
          } catch (e) {
            console.warn("Failed to set specify reason on Case", e);
          }
        }

        // --- email template - cms submission - additional items needed
        const isAdditionalItems =
          this.currentRule?.match ===
          "email template - cms submission - additional items needed";
        if (isAdditionalItems && this.isCase) {
          // 1) Additional Items Needed → save text to Case fields
          const additionalItemsTxt =
            this.valuesByKey?.documentationRequest || null;
          try {
            await setDocumentationRequest({
              caseId: this.recordId,
              insertInformation: additionalItemsTxt,
            });
          } catch (e) {
            console.warn("Failed to set Additional Items Needed on Case", e);
          }
        }

        // temporary exhaustion letter: msa - msprc-nghp - case
          const isTemporaryExhaustion =
          this.currentRule?.match ===
          "temporary exhaustion letter: msa - msprc-nghp - case";
        if (isTemporaryExhaustion && this.isCase) {
          // 1) nextAnnuityDate → save date to Case fields
          const nextAnnuityDateT =
            this.valuesByKey?.nextAnnuityDate || null;
          try {
            await setCaseNextAnnuityDate({
              caseId: this.recordId,
              insertDate: nextAnnuityDateT,
            });
          } catch (e) {
            console.warn("Failed to set Additional next Annuity Date on Case", e);
          }
        }

        // === Guardar Address en Administration si aplica (BEL) ===
        if (
          this.isCase &&
          (this.currentRule?.match === 'bel - wcmsa - case' || this.currentRule?.match !== 'prior auth not required') &&
          this.adminBELValidation &&
          this.adminBELValidation.hasAdministration === true &&
          this.adminBELValidation.hasFullAddress === false
        ) {
           const st = (this.valuesByKey?.state || "").trim().toUpperCase();

          try {
            await updateAdministrationAddress({
                adminId: this.adminId,
                street: this.valuesByKey?.street || null,
                city: this.valuesByKey?.city || null,
                state: (this.valuesByKey?.state || '').toUpperCase(),                 // State CODE (e.g., "CA")
                postalCode: this.valuesByKey?.postalCode || null,
                countryCodeOpt: (this.valuesByKey?.countryCode || '').toUpperCase()   // Country CODE (e.g., "US")
            });

            this.showToast("Success", "Administration address updated successfully.", "success");

            // Marca validación completa para no bloquear
            this.adminBELValidation = {
              ...this.adminBELValidation,
              hasFullAddress: true,
              missingFields: []
            };
          } catch (e) {
            this.showToast("Error", this.errMsg(e) || "Failed to update Administration address.", "error");
            this.loading = false;
            return;
          }

          const providerAttentionTxt =
            this.valuesByKey?.providerAttention || null;
          try {
            await setDocumentationRequest({
              caseId: this.recordId,
              insertInformation: providerAttentionTxt,
            });
          } catch (e) {
            console.warn("Failed to set Additional Items Needed on Case", e);
          }
        }
        // === /BEL ===

        // --- CRC/BCRC Letters: guardar LR dates + Address ---
        const isCrcOrBcrc =
          this.currentRule?.match === "crc letter initial appeal dispute" ||
          this.currentRule?.match === "crc letter level 1 appeal redetermination" ||
          this.currentRule?.match === "crc letter level 2 appeal reconsideration" ||
          this.currentRule?.match === "bcrc letter level 1 appeal redetermination" ||
          this.currentRule?.match === "bcrc letter initial appeal dispute";

        if (isCrcOrBcrc && this.isCase) {
          // 1) Address seleccionada (si existe)
          const selectedAddr = this.valuesByKey?.addressToUse || null;
          if (selectedAddr) {
            try {
              await setCaseAddress({ caseId: this.recordId, address: selectedAddr });
            } catch (e) {
              console.warn("Failed to persist Case.trm_Address__c (CRC/BCRC):", e);
            }
          }

          // 2) Fechas LR (algunas reglas no tienen datePriorIssued → pasa null)
          const dIssued = this.valuesByKey?.dateIssued || null;
          const dPrior  = this.valuesByKey?.datePriorIssued || null;

          try {
            await setCaseLRDates({
              caseId: this.recordId,
              dateIssued: dIssued,
              datePriorIssued: dPrior
            });
          } catch (e) {
            console.warn("Failed to set LR dates on Case:", e);
            // Si quieres bloquear el merge cuando falte algo, puedes hacer toast+return aquí
          }
        }



        // --- Mr Request: persist address + carrier/insurance + allocation company ---
        /*const isMrRequest =
          (this.currentRule?.match ===
          "mr request");
        if (isMrRequest && this.isCase) {
          // 1) Address → use existing setCaseAddress helper
          const selectedAddr = this.valuesByKey?.addressToUse || null;
          if (selectedAddr) {
            try {
              await setCaseAddress({
                caseId: this.recordId,
                address: selectedAddr,
              });
            } catch (e) {
              console.warn(
                "Failed to persist Case address fields (mr request)",
                e
              );
            }
          }
        }*/

        //docId = await mergeWithMapping(webmergePayload);

        // === BEGIN  immediate download  ===
        const payload = await mergeAndReturnFile({
          mappingId: this.selectedTemplateId,
          recordId: this.recordId,
          objectApiName: objectApiName,
        });

        // 1) Download file
        this.downloadBase64File(
          payload.fileName,
          payload.mimeType,
          payload.base64Data
        );

        // 2) Preserve existing behavior using the same docId
        docId = payload.contentDocumentId;
        // === END ===

        // Clear template fields after generation (only if rule declares a target field)
        try {
          if (this.currentRule?.targetFieldApi) {
            await updateCaseTemplateFields({
              caseId: this.recordId,
              targetFieldApi: this.currentRule.targetFieldApi,
              value: null,
              checkboxFieldApi: this.currentRule.checkboxFieldApi || null,
              checkboxValue: false,
            });
          } else {
            console.log(
              "ℹ️ No targetFieldApi in rule — skipping cleanup updateCaseTemplateFields"
            );
          }
        } catch (cleanupError) {
          console.warn(
            "Failed to clear template fields (guarded):",
            cleanupError
          );
        }

        console.log("🖥️ UI: mergeWithMapping returned docId =", docId);
      } else {
        // Simple document - use the production method
        console.log("Using basic generation for simple document");
        this.loadingMessage = "Generating document...";
        console.log("🖥️ UI: About to call mergeWithMapping");
        console.log("🖥️ UI: mappingId =", this.selectedTemplateId);
        console.log("🖥️ UI: recordId =", this.recordId);

        // 🚨 TRINITY WEBMERGE DEBUG: Log full object being sent to WebMerge (Simple Document)
        const webmergePayload = {
          mappingId: this.selectedTemplateId,
          recordId: this.recordId,
          objectApiName: objectApiName,
        };
        console.log(
          "🚀 TRINITY WEBMERGE DEBUG: Full payload being sent to mergeWithMapping (SIMPLE DOC):"
        );
        console.log(
          "📦 Payload Object:",
          JSON.stringify(webmergePayload, null, 2)
        );
        console.log("🔍 Payload Details:");
        console.log(
          "  - mappingId (selectedTemplateId):",
          webmergePayload.mappingId
        );
        console.log("  - recordId:", webmergePayload.recordId);
        console.log("  - objectApiName:", webmergePayload.objectApiName);

        if (this.currentInputs?.length) {
          if (this.isCase && this.currentRule?.match === "attestation") {
            const s = this.valuesByKey.dateStart || null;
            const e = this.valuesByKey.dateEnd || null;
            await setCasePeriodDates({
              caseId: this.recordId,
              dateStart: s,
              dateEnd: e,
            });
          }
        }

        // NEW block
        if (this.currentRule?.match === "temp exhaustion mca") {
          // 1) save Annuity (currency)  Case.trm_Annuity__c
          const raw = this.valuesByKey?.annuity;
          const amount = raw !== null && raw !== undefined ? Number(raw) : NaN;
          try {
            await setCaseAnnuity({
              caseId: this.recordId,
              annuity: isFinite(amount) ? amount : null,
            });
          } catch (e) {
            console.warn("Failed to set Case Annuity (simple branch):", e);
          }

          // 2) map exhaustion active
          try {
            await mapClosestActiveExhaustionToCase({ caseId: this.recordId });
          } catch (e) {
            console.warn(
              "Failed to map closest active Exhaustion (simple branch):",
              e
            );
          }
        }

        //docId = await mergeWithMapping(webmergePayload);
        // === BEGIN patch: maintain behavior + add immediate download  ===
        const payload = await mergeAndReturnFile({
          mappingId: this.selectedTemplateId,
          recordId: this.recordId,
          objectApiName: objectApiName,
        });

        // 1) Download NOW
        this.downloadBase64File(
          payload.fileName,
          payload.mimeType,
          payload.base64Data
        );

        // 2) Retain existing behavior
        docId = payload.contentDocumentId;
        // === END parche ===

        console.log("🖥️ UI: mergeWithMapping returned docId =", docId);
      }

      console.log("🖥️ UI: FINAL docId before file opening:", docId);

      if (docId) {
        // Update loading message
        this.loadingMessage = "Completing...";
        await this.delay(200);

        // Refresh the host record view to show new file in Files related list
        this.refreshHostRecordView();

        // Show success toast with clickable link to document
        //this.showToastWithLink('Document Generated Successfully!', 'View Document', docId);
        this.showToast(
          "Document Generated Successfully!",
          "Please check your downloads folder",
          "success"
        );
      } else {
        this.showToast(
          "Merge complete",
          "No file was immediately available. Check the Files related list or mapping settings.",
          "warning"
        );
      }
    } catch (error) {
      console.error("Document generation error:", error);
      const errorMessage = this.errMsg(error);
      this.showToast("Merge failed", errorMessage, "error");
    } finally {
      // Smooth loading state transition
      this.loadingMessage = "Completing...";
      await this.delay(300);
      this.loading = false;
    }
  }

  // Add missing showToast method
  showToast(title, message, variant) {
    const event = new ShowToastEvent({
      title: title,
      message: message,
      variant: variant,
    });
    this.dispatchEvent(event);
  }

  // Show success toast with clickable link to document
  showToastWithLink(title, linkLabel, docId) {
    const event = new ShowToastEvent({
      title: title,
      message: "Your document is ready. {0}",
      messageData: [
        {
          url: "/lightning/r/ContentDocument/" + docId + "/view",
          label: linkLabel,
        },
      ],
      variant: "success",
    });
    this.dispatchEvent(event);
  }

  // Add errMsg helper from original production code
  errMsg(err) {
    try {
      if (typeof err === "string") return err;
      if (err?.body?.message) return err.body.message;
      return JSON.stringify(err);
    } catch (e) {
      return "Unexpected error";
    }
  }

  // ---------- Object Type Detection ----------
  get isCase() {
    console.log("isCase");
    return this.recordId?.startsWith("500");
  }

  get isMemberAccount() {
    console.log("isMemberAccount");
    return this.recordId?.startsWith("a05");
  }

  get isAdministration() {
    console.log("isAdministration");
    return this.recordId?.startsWith("a03");
  }

  get isDeniedRefund() {
    console.log("isDeniedRefund");
    return this.recordId?.startsWith("a2A");
  }

  get isEntity() {
    console.log("isEntity");
    return this.recordId?.startsWith("001");
  }

  get isExhaustion() {
    console.log("isExhaustion");
    return this.recordId?.startsWith("a09");
  }

  getObjectApiName() {
    if (!this.recordId) return "Case"; // Default fallback

    // Salesforce record ID prefixes for supported objects
    const prefixMap = {
      500: "Case",
      "001": "Account", //  Entity - Account -	Standard Object
      // Add other object prefixes as needed when team confirms them
      a05: "Member_Account__c",
      a03: "Administration__c",
      a2A: "Denied_Refund__c",
      // 'XXX': 'Entity__c'
      a09: "Exhaustion__c",
    };

    const prefix = this.recordId.substring(0, 3);
    console.log("prefixMap", prefix);
    console.log("this.recordId", this.recordId);
    return prefixMap[prefix] || "Case"; // Default to Case if unknown
  }

  // ---------- Helper methods for smooth UX ----------
  delay(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
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
          console.error("All file opening attempts failed:", e);
          return false;
        }
      }
    }
    return false;
  }

  async openFileRecord(docId) {
    try {
      console.log("🖥️ UI: openFileRecord called with docId =", docId);

      // Use the production pattern from original_webmerge.txt
      // Check if we're in console navigation first
      if (await isConsoleNavigation()) {
        console.log("🖥️ UI: Using console navigation to open docId =", docId);
        await openTab({ recordId: docId, focus: true });
      } else {
        console.log("🖥️ UI: Using standard navigation to open docId =", docId);
        this[NavigationMixin.Navigate]({
          type: "standard__recordPage",
          attributes: {
            recordId: docId,
            objectApiName: "ContentDocument",
            actionName: "view",
          },
        });
      }
    } catch (e) {
      console.error("Error opening file record:", e);
      // Fallback to file preview
      this[NavigationMixin.Navigate]({
        type: "standard__namedPage",
        attributes: { pageName: "filePreview" },
        state: { selectedRecordId: docId },
      });
    }
  }

  refreshHostRecordView() {
    try {
      // Use the proper LWC way to refresh record data
      getRecordNotifyChange([{ recordId: this.recordId }]);
    } catch (e) {
      console.warn("getRecordNotifyChange failed, trying legacy refresh:", e);
      try {
        // Fallback to legacy Aura refresh
        eval("$A.get('e.force:refreshView').fire();");
      } catch (e2) {
        console.warn("Legacy refresh also failed:", e2);
        // Final fallback - show message to user
        this.showToast(
          "Info",
          "Document generated. Please refresh the page to see the new file in the Files related list.",
          "info"
        );
      }
    }
  }

  // -------- util visual: marcar selección (sin llamadas en template) --------
  markSelectedInArray(arr, key, val) {
    if (!arr) return;
    arr.forEach((item) => {
      const base = "pill";
      item.className = val && item[key] === val ? base + " selected" : base;
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
    for (let i = 0; i < byteChars.length; i++)
      byteNumbers[i] = byteChars.charCodeAt(i);
    const byteArray = new Uint8Array(byteNumbers);
    const blob = new Blob([byteArray], { type: mimeType });

    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = fileName || "document";
    document.body.appendChild(a);
    a.click();
    a.remove();
    URL.revokeObjectURL(url);
  }
  // ====== /DOWNLOAD-IMMEDIATE SUPPORT ======

  debounce(fn, wait) {
    return (...args) => {
      clearTimeout(this._codeSearchDebounce);
      this._codeSearchDebounce = setTimeout(() => fn.apply(this, args), wait);
    };
  }

  searchCodesDebounced = this.debounce(async (term) => {
    try {
      const opts = await searchCodes({ term });
      // Opciones a [{label, value}]
      this.codeOptions = (opts || []).map((o) => ({
        label: o.label,
        value: o.value,
      }));
      // Refresca inputs renderizados
      this.currentInputs = [...this.currentInputs];
    } catch (e) {
      console.warn("Code search failed", e);
      this.codeOptions = [];
    }
  }, 250);

  get hasCodeOptions() {
    return Array.isArray(this.codeOptions) && this.codeOptions.length > 0;
  }
  isLookup(inp) {
    return inp && inp._renderType === "lookup";
  }
  get lookupComboboxClass() {
    // Abre el dropdown cuando hay resultados
    return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${
      this.hasCodeOptions ? "slds-is-open" : ""
    }`;
  }
  get isLookupMissing() {
    // requerido si definiste diagnosisCodeId como required
    return (
      this.currentInputs.some(
        (i) => i.key === "diagnosisCodeId" && i.required
      ) && !this.valuesByKey?.diagnosisCodeId
    );
  }

  handleLookupTyping = (e) => {
    // e.target is the <lightning-input type="search">
    const typed = (e.target.value || "").trim();
    // Guarda el término visible:
    this.valuesByKey = { ...this.valuesByKey, diagnosisSearch: typed };

    if (typed.length >= 2) {
      this.searchCodesDebounced(typed);
    } else {
      this.codeOptions = [];
    }
  };

  handleSelectCode = (e) => {
    const id = e.currentTarget.dataset.id;
    const label = e.currentTarget.dataset.label;

    // Guarda el lookup (Id real) y el texto visible
    this.valuesByKey = {
      ...this.valuesByKey,
      diagnosisCodeId: id,
      diagnosisSearch: label,
    };

    // Cierra el dropdown
    this.codeOptions = [];
  };

  handleLookupKeydown = (e) => {
    if (e.key === "Escape") {
      this.codeOptions = [];
    }
    if (e.key === "Enter" && this.codeOptions.length === 1) {
      // Autoselección rápida si hay 1 resultado
      const only = this.codeOptions[0];
      this.valuesByKey = {
        ...this.valuesByKey,
        diagnosisCodeId: only.value,
        diagnosisSearch: only.label,
      };
      this.codeOptions = [];
    }
    // (Si quieres manejo de flechas, tendrías que llevar un índice seleccionado)
  };


  // Build state options from cached wire metadata; no imperative wire calls here
  async loadStateOptions(countryCode) {
    try {
      // Need the recordTypeId (set by getObjectInfo) and a country to filter on
      if (!this.recordTypeId || !countryCode) {
        this.stateOptions = [];
        return;
      }

      // If wire hasn't delivered data yet, there is nothing to filter
      if (!this._stateAllValues.length || !this._controllerMap) {
        this.stateOptions = [];
        return;
      }

      const idx = this._controllerMap[countryCode];
      if (idx === undefined) {
        this.stateOptions = [];
        return;
      }

      // Filter states whose validFor contains country index
      this.stateOptions = this._stateAllValues
        .filter(v => Array.isArray(v.validFor) && v.validFor.includes(idx))
        .map(v => ({ value: v.value, label: v.label }));

      // If currently selected state is no longer valid, clear it
      if (!this.stateOptions.find(o => o.value === this.valuesByKey?.state)) {
        this.valuesByKey = { ...(this.valuesByKey || {}), state: null };
      }
    } catch (e) {
      this.stateOptions = [];
    }
  }



    isBelAddressValid() {
    if (!this.currentRule || (this.currentRule.match !== 'bel - wcmsa - case' || this.currentRule?.match)) return true;

    // Si no hay Administration, bloquear
    if (!this.adminBELValidation?.hasAdministration) return false;

    // Si estamos pidiendo completar address, valida requeridos
    if (!this.adminBELValidation.hasFullAddress) {
      const v = this.valuesByKey || {};
      const requiredOk =
        v.street && v.city && v.postalCode && v.countryCode && v.state;

      return !!requiredOk;
    }
    return true;
  }


}