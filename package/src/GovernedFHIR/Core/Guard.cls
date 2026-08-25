/// Every restriction in one place.
/// Plain ObjectScript, no AI Hub dependency
Class GovernedFHIR.Core.Guard Extends %RegisteredObject
{

Parameter MAXROWS As INTEGER = 25;

Parameter MAXCHARS As INTEGER = 12000;

Parameter MAXPATIENTS As INTEGER = 10;

ClassMethod AllowedResources() As %String
{
	Return "Condition,Observation,MedicationRequest,AllergyIntolerance,Encounter,Immunization,Procedure"
}

/// Anything not listed will be rejected
ClassMethod AllowedParams(resourceType As %String) As %String
{
	Return $Case(resourceType,
		"Condition":          "clinical-status,category,code,onset-date,recorded-date,_sort,_count",
		"Observation":        "category,code,date,status,_sort,_count",
		"MedicationRequest":  "status,intent,authoredon,_sort,_count",
		"AllergyIntolerance": "clinical-status,category,_sort,_count",
		"Encounter":          "status,class,date,_sort,_count",
		"Immunization":       "status,date,_sort,_count",
		"Procedure":          "status,date,code,_sort,_count",
		:                     "")
}

ClassMethod IsResourceAllowed(resourceType As %String) As %Boolean
{
	If resourceType = "" Return 0
	Return ("," _ ..AllowedResources() _ ",") [ ("," _ resourceType _ ",")
}

ClassMethod IsParamAllowed(
	resourceType As %String,
	param As %String) As %Boolean
{
	If param = "" Return 0
	Return ("," _ ..AllowedParams(resourceType) _ ",") [ ("," _ param _ ",")
}

/// FHIR ids are [A-Za-z0-9-.]{1,64}
ClassMethod IsPatientIdValid(patientId As %String) As %Boolean
{
	Return patientId?1.64(1AN,1"-",1".")
}

/// Build validated query string. Returns "" and sets reason when the request rejected
ClassMethod BuildPatientQuery(
	resourceType As %String,
	patientId As %String,
	params As %DynamicObject = "",
	Output reason As %String) As %String
{
	Set reason = ""

	If '..IsResourceAllowed(resourceType) {
		Set reason = "resource type '"_resourceType_"' is not exposed, Allowed: "_..AllowedResources()
		Return ""
	}
	If '..IsPatientIdValid(patientId) {
		Set reason = "a valid patientId is required; resolve the patient first"
		Return ""
	}

	Set query = "patient=Patient/"_patientId
	Set count = ""

	If $IsObject($Get(params)) {
		Set iter = params.%GetIterator()
		While iter.%GetNext(.key, .value) {
			If key = "patient" Continue
			If '..IsParamAllowed(resourceType, key) {
				Set reason = "search parameter '"_key_"' is not allowed for "_resourceType_", Allowed: "_..AllowedParams(resourceType)
				Return ""
			}
			If key = "_count" {
				Set count = ..ClampCount(value)
				Continue
			}
			If value = "" Continue
			Set query = query_"&"_key_"="_..EncodeValue(value)
		}
	}

	If count = "" Set count = ..#MAXROWS
	Set query = query_"&_count="_count
	Return query
}

ClassMethod ClampCount(value As %String) As %Integer
{
	Set n = +value
	If n < 1 Return ..#MAXROWS
	If n > ..#MAXROWS Return ..#MAXROWS
	Return n
}

/// Percent-encode, and strip other smuggles
ClassMethod EncodeValue(value As %String) As %String
{
	Set value = $Translate(value, "&?#", "   ")
	Return $ZConvert(value, "O", "URL")
}

// If fits - skip
ClassMethod CapPayload(
	json As %String,
	Output truncated As %Boolean) As %String
{
	Set truncated = 0
	If $Length(json) <= ..#MAXCHARS Return json
	Set truncated = 1
	Return {"error":"result_too_large","message":"The result exceeded the size limit for a single tool call. Narrow the query - add a date range, a code or a category - and try again","limitChars":(..#MAXCHARS)}.%ToJSON()
}

/// Every denial looks the same to the model
ClassMethod Deny(reason As %String) As %String
{
	Return {"error":"denied","message":(reason)}.%ToJSON()
}

}
