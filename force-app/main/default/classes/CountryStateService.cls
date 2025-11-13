// CountryStateService.cls
public with sharing class CountryStateService {

    /**
     * Returns the active Country picklist (code -> label) from your org.
     * Leverages User.CountryCode global catalog so you don't hardcode countries.
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getCountryCodeToLabelMap() {
        Map<String, String> out = new Map<String, String>();
        for (Schema.PicklistEntry pe : User.CountryCode.getDescribe().getPicklistValues()) {
            if (pe.isActive()) out.put(pe.getValue(), pe.getLabel()); // e.g., "US" -> "United States"
        }
        return out;
    }
}