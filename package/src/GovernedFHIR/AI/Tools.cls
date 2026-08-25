Class GovernedFHIR.AI.Tools Extends %AI.Tool [ DependsOn = (GovernedFHIR.Core.Repo, GovernedFHIR.Core.Guard, GovernedFHIR.Core.Projection) ]
{

Parameter DESCRIPTION = "Read-only, patient-scoped access to an InterSystems IRIS for Health FHIR R4 repository.";

Parameter DISCOVERYLIMIT = "GovernedFHIR.AI.Tools";

/// Find patients by name, birth date, or identifier. Returns at most 10 compact
/// matches, each with a patientId. Every other tool needs a patientId from here.
/// Returns an empty match list rather than guessing when nothing matches -
/// never invent a patientId.
/// name is a family or given name fragment; birthDate is YYYY-MM-DD;
/// identifier is an MRN or other business identifier.
ClassMethod FindPatient(
	name As %String(DESCRIPTION="Family or given name fragment") = "",
	birthDate As %String(DESCRIPTION="Date of birth, YYYY-MM-DD") = "",
	identifier As %String(DESCRIPTION="MRN or other business identifier") = "") As %String [ WebMethod ]
{
	If (name = "") && (birthDate = "") && (identifier = "") {
		Return ##class(GovernedFHIR.Core.Guard).Deny("supply at least one of: name, birthDate, identifier")
	}

	Set query = ""
	If name '= "" Set query = query_"&name="_##class(GovernedFHIR.Core.Guard).EncodeValue(name)
	If birthDate '= "" Set query = query_"&birthdate="_##class(GovernedFHIR.Core.Guard).EncodeValue(birthDate)
	If identifier '= "" Set query = query_"&identifier="_##class(GovernedFHIR.Core.Guard).EncodeValue(identifier)
	Set query = $Extract(query, 2, *)_"&_count="_##class(GovernedFHIR.Core.Guard).#MAXPATIENTS

	Set bundle = ##class(GovernedFHIR.Core.Repo).Search("Patient", query, .outcome)
	If outcome '= "" Return ##class(GovernedFHIR.Core.Guard).Deny(outcome)

	Set matches = ##class(GovernedFHIR.Core.Projection).Bundle(bundle)
	Set total = $Select(bundle.%IsDefined("total"): +bundle.total, 1: matches.%Size())
	Set out = {
		"matches": (matches),
		"returned": (matches.%Size()),
		"total": (total)
	}
	If total > ##class(GovernedFHIR.Core.Guard).#MAXPATIENTS {
		Set out.note = "More matches exist than were returned. Narrow the search before choosing a patient."
	}
	Return ##class(GovernedFHIR.Core.Guard).CapPayload(out.%ToJSON(), .truncated)
}

/// Return a compact clinical summary for one patient: active conditions, recent
/// vital signs and laboratory results, active medication requests, and known
/// allergies. Requires a patientId obtained from FindPatient. Each item carries
/// its FHIR resource id so findings can be traced back to the record.
ClassMethod GetPatientSummary(patientId As %String(DESCRIPTION="FHIR Patient id returned by FindPatient")) As %String [ WebMethod ]
{
	If '##class(GovernedFHIR.Core.Guard).IsPatientIdValid(patientId) {
		Return ##class(GovernedFHIR.Core.Guard).Deny("a valid patientId is required - call FindPatient first")
	}

	Set patient = ##class(GovernedFHIR.Core.Repo).Read("Patient", patientId, .outcome)
	If outcome '= "" Return ##class(GovernedFHIR.Core.Guard).Deny("patient "_patientId_" not readable: "_outcome)

	Set out = {}
	Set out.patient = ##class(GovernedFHIR.Core.Projection).ByType(patient)
	Set out.conditions = ..Section("Condition", patientId, {"clinical-status":"active", "_count":10})
	Set out.vitals = ..LatestByCode(..Section("Observation", patientId, {"category":"vital-signs", "_sort":"-date", "_count":20}))
	Set out.labs = ..LatestByCode(..Section("Observation", patientId, {"category":"laboratory", "_sort":"-date", "_count":20}))
	Set out.medications = ..Section("MedicationRequest", patientId, {"status":"active", "_count":10})
	Set out.allergies = ..Section("AllergyIntolerance", patientId, {"_count":10})

	Set json = ##class(GovernedFHIR.Core.Guard).CapPayload(out.%ToJSON(), .truncated)
	If truncated {
		// Rather than return nothing, drop the two lowest-priority sections.
		Do out.%Remove("labs")
		Do out.%Remove("vitals")
		Set out.note = "Vital signs and laboratory results were omitted because the summary exceeded the size limit. Use FhirSearch on Observation with a narrower category, code, or date range."
		Set json = ##class(GovernedFHIR.Core.Guard).CapPayload(out.%ToJSON(), .truncated)
	}
	Return json
}

/// Search one clinical resource type inside a single patient's compartment.
/// resourceType must be one of: Condition, Observation, MedicationRequest,
/// AllergyIntolerance, Encounter, Immunization, Procedure.
/// params is a JSON object of FHIR search parameters, for example
/// {"category":"laboratory","date":"ge2024-01-01"}. Unsupported parameters are
/// rejected with the list of allowed ones - read the error and retry.
/// The patient scope is applied by the server and cannot be overridden.
ClassMethod FhirSearch(
	resourceType As %String(DESCRIPTION="Condition, Observation, MedicationRequest, AllergyIntolerance, Encounter, Immunization or Procedure"),
	patientId As %String(DESCRIPTION="FHIR Patient id returned by FindPatient"),
	params As %DynamicObject(DESCRIPTION="JSON object of FHIR search parameters") = "") As %String [ WebMethod ]
{
	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery(resourceType, patientId, params, .reason)
	If query = "" Return ##class(GovernedFHIR.Core.Guard).Deny(reason)

	Set bundle = ##class(GovernedFHIR.Core.Repo).Search(resourceType, query, .outcome)
	If outcome '= "" Return ##class(GovernedFHIR.Core.Guard).Deny(outcome)

	Set items = ##class(GovernedFHIR.Core.Projection).Bundle(bundle)
	Set out = {
		"resourceType": (resourceType),
		"patientId": (patientId),
		"items": (items),
		"returned": (items.%Size()),
		"total": ($Select(bundle.%IsDefined("total"): +bundle.total, 1: items.%Size()))
	}
	Return ##class(GovernedFHIR.Core.Guard).CapPayload(out.%ToJSON(), .truncated)
}

/// A summary wants the current value of each measurement, not the last N rows.
/// Synthea repeats the same panel at every encounter, so "recent vitals" comes
/// back as five measurements twice over - which reads as history the clinician
/// did not ask for, and hands the model twice as many near-identical ids to keep
/// straight. The search is already sorted newest first, so the first occurrence
/// of a code is the current one.
ClassMethod LatestByCode(items As %DynamicArray) As %DynamicArray [ Internal ]
{
	Set out = [], seen = ""
	Set iter = items.%GetIterator()
	While iter.%GetNext(.i, .item) {
		Set key = $Extract(item.code, 1, 200)
		If key = "" Set key = item.id
		If $Data(seen(key)) Continue
		Set seen(key) = 1
		Do out.%Push(item)
	}
	Return out
}

/// Compartment-locked search. Section of the summary, and on failure an empty one - a missing section is not worth failing the summary
ClassMethod Section(
	resourceType As %String,
	patientId As %String,
	params As %DynamicObject) As %DynamicArray [ Internal, Private ]
{
	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery(resourceType, patientId, params, .reason)
	If query = "" Return []
	Set bundle = ##class(GovernedFHIR.Core.Repo).Search(resourceType, query, .outcome)
	If outcome '= "" Return []
	Return ##class(GovernedFHIR.Core.Projection).Bundle(bundle)
}

}
