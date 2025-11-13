public with sharing class AgentFieldWriter {
    @AuraEnabled
    public static void writeAgentToMapping(Id mappingId) {
        if (mappingId == null) return;

        User u = [
            SELECT Id, FirstName, LastName, Name, Title, Phone
            FROM User
            WHERE Id = :UserInfo.getUserId()
            LIMIT 1
        ];
        String firstName = (u.FirstName != null) ? u.FirstName : parseFirstName(u.Name);
        String lastName  = (u.LastName  != null) ? u.LastName  : parseLastName(u.Name);
        String ext       = parseExtension(u.Phone);
        String title     = u.Title;

        Schema.DescribeSObjectResult d = webm__Webmerge_Mapping__c.SObjectType.getDescribe();
        if (!d.isAccessible()) return;

        Map<String, Schema.SObjectField> fmap = d.fields.getMap();

        webm__Webmerge_Mapping__c m = new webm__Webmerge_Mapping__c(Id = mappingId);
        Boolean upd = false;

        if (fmap.containsKey('trm_Agent_First_Field__c') && fmap.get('trm_Agent_First_Field__c').getDescribe().isUpdateable()) { m.put('trm_Agent_First_Field__c', firstName); upd = true; }
        if (fmap.containsKey('trm_Agent_Last_Field__c')  && fmap.get('trm_Agent_Last_Field__c').getDescribe().isUpdateable())  { m.put('trm_Agent_Last_Field__c',  lastName);  upd = true; }
        if (fmap.containsKey('trm_Agent_Ext_Field__c')   && fmap.get('trm_Agent_Ext_Field__c').getDescribe().isUpdateable())   { m.put('trm_Agent_Ext_Field__c',   ext);      upd = true; }
        if (fmap.containsKey('trm_Agent_Title_Field__c') && fmap.get('trm_Agent_Title_Field__c').getDescribe().isUpdateable()) { m.put('trm_Agent_Title_Field__c', title);    upd = true; }

        if (upd) update m;
    }

    private static String parseFirstName(String fullName) {
        if (String.isBlank(fullName)) return null;
        List<String> p = fullName.trim().split('\\s+');
        return p.isEmpty() ? null : p[0];
    }
    private static String parseLastName(String fullName) {
        if (String.isBlank(fullName)) return null;
        List<String> p = fullName.trim().split('\\s+'); if (p.size() <= 1) return null;
        p.remove(0); return String.join(p, ' ');
    }
    private static String parseExtension(String phone) {
        if (String.isBlank(phone)) return null;
        Pattern pt = Pattern.compile('(?i)(?:ext|x)\\s*(\\d+)'); Matcher m = pt.matcher(phone);
        return m.find() ? m.group(1) : null;
    }
}