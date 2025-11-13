declare module "@salesforce/apex/DocumentRequestController.fetchDepartments" {
  export default function fetchDepartments(): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.fetchSubDepartments" {
  export default function fetchSubDepartments(): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.fetchSubDepartmentsByDepartment" {
  export default function fetchSubDepartmentsByDepartment(param: {department: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.searchMappingsByName" {
  export default function searchMappingsByName(param: {term: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.fetchDocumentsUnified" {
  export default function fetchDocumentsUnified(param: {departmentInputs: any, subDepartmentNames: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.mergeWithMapping" {
  export default function mergeWithMapping(param: {mappingId: any, recordId: any, objectApiName: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.generateWithEnhancedFeatures" {
  export default function generateWithEnhancedFeatures(param: {mappingId: any, recordId: any, templateContent: any, targetFieldApi: any, checkboxFieldApi: any, checkboxValue: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.updateCaseTemplateFields" {
  export default function updateCaseTemplateFields(param: {caseId: any, targetFieldApi: any, value: any, checkboxFieldApi: any, checkboxValue: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.updateAgentFields" {
  export default function updateAgentFields(param: {recordId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.mergeAndReturnFile" {
  export default function mergeAndReturnFile(param: {mappingId: any, recordId: any, objectApiName: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCasePeriodDates" {
  export default function setCasePeriodDates(param: {caseId: any, dateStart: any, dateEnd: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.clearCasePeriodDates" {
  export default function clearCasePeriodDates(param: {caseId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseAnnuity" {
  export default function setCaseAnnuity(param: {caseId: any, annuity: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseFundingChange" {
  export default function setCaseFundingChange(param: {caseId: any, fundingChange: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.fetchPayeeAddresses" {
  export default function fetchPayeeAddresses(param: {caseId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.fetchAccountAddresses" {
  export default function fetchAccountAddresses(param: {caseId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseAddress" {
  export default function setCaseAddress(param: {caseId: any, address: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseInsertInformation" {
  export default function setCaseInsertInformation(param: {caseId: any, insertInformation: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.searchCodes" {
  export default function searchCodes(param: {term: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseInjuredDiagnosis" {
  export default function setCaseInjuredDiagnosis(param: {caseId: any, codeId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseWithdrawalExtras" {
  export default function setCaseWithdrawalExtras(param: {caseId: any, carrierOrInsurance: any, allocationCompany: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setSpecifyReason" {
  export default function setSpecifyReason(param: {caseId: any, insertInformation: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setDocumentationRequest" {
  export default function setDocumentationRequest(param: {caseId: any, insertInformation: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setProviderAttention" {
  export default function setProviderAttention(param: {caseId: any, providerAttention: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseNextAnnuityDate" {
  export default function setCaseNextAnnuityDate(param: {caseId: any, insertDate: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.fetchExhaustionsForCase" {
  export default function fetchExhaustionsForCase(param: {caseId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseExhaustion" {
  export default function setCaseExhaustion(param: {caseId: any, exhaustionId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.validateBELAdmin" {
  export default function validateBELAdmin(param: {caseId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.updateAdministrationAddress" {
  export default function updateAdministrationAddress(param: {adminId: any, street: any, city: any, state: any, postalCode: any, countryCodeOpt: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.getCountryCodeToLabelMap" {
  export default function getCountryCodeToLabelMap(): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.getStateCodeToLabelMap" {
  export default function getStateCodeToLabelMap(param: {countryCode: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseLRDates" {
  export default function setCaseLRDates(param: {caseId: any, dateIssued: any, datePriorIssued: any}): Promise<any>;
}
