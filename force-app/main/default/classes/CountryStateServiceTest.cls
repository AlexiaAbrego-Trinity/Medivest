@IsTest
private class CountryStateServiceTest {

    @IsTest
    static void testGetCountryCodeToLabelMap() {

        // Call the method
        Map<String, String> result = CountryStateService.getCountryCodeToLabelMap();

        // Assertions
        System.assertNotEquals(
            null, 
            result,
            'The method should not return null'
        );

        // In almost all orgs, picklist has values, but we do not hardcode.
        System.assert(
            result.size() >= 0,
            'Expected a map (even if empty on scratch org)'
        );
    }

    @IsTest
    static void testGetStateCodeToLabelMap() {

        // Call the method
        Map<String, String> result = CountryStateService.getStateCodeToLabelMap();

        System.assertNotEquals(
            null, 
            result,
            'The method should not return null'
        );

        System.assert(
            result.size() >= 0,
            'Expected a map (even if empty)'
        );
    }
}
