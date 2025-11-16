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
declare module "@salesforce/apex/DocumentRequestController.fetchClaims" {
  export default function fetchClaims(param: {parentId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.updateSelectedClaims" {
  export default function updateSelectedClaims(param: {recordId: any, claimIds: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.fetchPayeeAddresses" {
  export default function fetchPayeeAddresses(param: {caseId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.setCaseAddress" {
  export default function setCaseAddress(param: {caseId: any, address: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.searchCodes" {
  export default function searchCodes(param: {term: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.searchCodesForDiagnosis" {
  export default function searchCodesForDiagnosis(param: {term: any, codeType: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.updateCaseDiagnosisCodes" {
  export default function updateCaseDiagnosisCodes(param: {caseId: any, codeId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.fetchDiagnosisContextForCase" {
  export default function fetchDiagnosisContextForCase(param: {caseId: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.searchCodesByType" {
  export default function searchCodesByType(param: {term: any, codeType: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.searchIcdCodes" {
  export default function searchIcdCodes(param: {term: any, icdType: any}): Promise<any>;
}
declare module "@salesforce/apex/DocumentRequestController.updateDiagnosisCodes" {
  export default function updateDiagnosisCodes(param: {caseId: any, icd9Id: any, icd10Id: any}): Promise<any>;
}
