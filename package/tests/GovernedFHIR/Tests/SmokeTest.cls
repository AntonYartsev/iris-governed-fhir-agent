/// End-to-end checks that need the FHIR endpoint and the bundled dataset, but
/// still no LLM. Skipped automatically when the repository is empty, so the
/// suite stays green on a bare IRIS.
Class GovernedFHIR.Tests.SmokeTest Extends %UnitTest.TestCase
{

Method TestFhirEndpointResponds()
{
	Do $$$AssertTrue(##class(GovernedFHIR.Core.Repo).IsReady(), "FHIR endpoint answers /metadata")
}

Method TestFindPatientReturnsIds()
{
	If ##class(GovernedFHIR.Setup.Install).PatientCount() = 0 {
		Do $$$LogMessage("No patients loaded - skipping")
		Quit
	}
	Set json = ##class(GovernedFHIR.AI.Tools).FindPatient("a")
	Set out = {}.%FromJSON(json)
	Do $$$AssertNotTrue(out.%IsDefined("error"), "lookup succeeded")
	Do $$$AssertTrue(out.returned > 0, "at least one match")
	Do $$$AssertTrue(out.returned <= ##class(GovernedFHIR.Core.Guard).#MAXPATIENTS, "match count is capped")
	Set first = out.matches.%Get(0)
	Do $$$AssertNotEquals(first.id, "", "match carries a patient id")
}

Method TestFindPatientRequiresACriterion()
{
	Set out = {}.%FromJSON(##class(GovernedFHIR.AI.Tools).FindPatient())
	Do $$$AssertEquals(out.error, "denied", "empty lookup is refused")
}

Method TestSearchWithoutPatientIsRefused()
{
	Set out = {}.%FromJSON(##class(GovernedFHIR.AI.Tools).FhirSearch("Observation", ""))
	Do $$$AssertEquals(out.error, "denied", "search without a patient is refused")
}

/// Encounter, Immunization and Procedure all fall through to the generic
/// projection, and each one names its code and date differently
Method TestGenericProjectionFillsCodeAndDate()
{
	If ##class(GovernedFHIR.Setup.Install).PatientCount() = 0 {
		Do $$$LogMessage("No patients loaded - skipping")
		Quit
	}
	Set lookup = {}.%FromJSON(##class(GovernedFHIR.AI.Tools).FindPatient("a"))
	Set patientId = lookup.matches.%Get(0).id

	For type = "Encounter","Immunization","Procedure" {
		Set out = {}.%FromJSON(##class(GovernedFHIR.AI.Tools).FhirSearch(type, patientId))
		If out.returned = 0 {
			Do $$$LogMessage("No "_type_" for this patient - skipping")
			Continue
		}
		Set item = out.items.%Get(0)
		Do $$$AssertNotEquals(item.code, "", type_" carries a code")
		Do $$$AssertNotEquals(item.date, "", type_" carries a date")
	}
}

Method TestSummaryShape()
{
	If ##class(GovernedFHIR.Setup.Install).PatientCount() = 0 {
		Do $$$LogMessage("No patients loaded - skipping")
		Quit
	}
	Set lookup = {}.%FromJSON(##class(GovernedFHIR.AI.Tools).FindPatient("a"))
	Set patientId = lookup.matches.%Get(0).id

	Set out = {}.%FromJSON(##class(GovernedFHIR.AI.Tools).GetPatientSummary(patientId))
	Do $$$AssertNotTrue(out.%IsDefined("error"), "summary succeeded")
	Do $$$AssertEquals(out.patient.id, patientId, "summary is for the requested patient")
	Do $$$AssertTrue(out.%IsDefined("conditions"), "conditions section present")
	Do $$$AssertTrue(out.%IsDefined("medications"), "medications section present")
	Do $$$AssertTrue($Length(##class(GovernedFHIR.AI.Tools).GetPatientSummary(patientId)) <= ##class(GovernedFHIR.Core.Guard).#MAXCHARS, "summary respects the size cap")
}

}
