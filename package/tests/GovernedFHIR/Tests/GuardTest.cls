/// No LLM, no network, no API key, no remose
Class GovernedFHIR.Tests.GuardTest Extends %UnitTest.TestCase
{

Method TestResourceAllowlist()
{
	Do $$$AssertTrue(##class(GovernedFHIR.Core.Guard).IsResourceAllowed("Observation"), "Observation is allowed")
	Do $$$AssertTrue(##class(GovernedFHIR.Core.Guard).IsResourceAllowed("Condition"), "Condition is allowed")
	Do $$$AssertNotTrue(##class(GovernedFHIR.Core.Guard).IsResourceAllowed("Practitioner"), "Practitioner is not exposed")
	Do $$$AssertNotTrue(##class(GovernedFHIR.Core.Guard).IsResourceAllowed("Binary"), "Binary is not exposed")
	Do $$$AssertNotTrue(##class(GovernedFHIR.Core.Guard).IsResourceAllowed(""), "empty resource type is rejected")
}

Method TestPatientIdValidation()
{
	Do $$$AssertTrue(##class(GovernedFHIR.Core.Guard).IsPatientIdValid("1a2b-3c.4d"), "well-formed FHIR id accepted")
	Do $$$AssertNotTrue(##class(GovernedFHIR.Core.Guard).IsPatientIdValid(""), "empty id rejected")
	Do $$$AssertNotTrue(##class(GovernedFHIR.Core.Guard).IsPatientIdValid("1&_count=1000"), "parameter injection rejected")
	Do $$$AssertNotTrue(##class(GovernedFHIR.Core.Guard).IsPatientIdValid("../Practitioner"), "path traversal rejected")
	Do $$$AssertNotTrue(##class(GovernedFHIR.Core.Guard).IsPatientIdValid($Translate($Justify("", 65), " ", "a")), "over-long id rejected")
}

Method TestCompartmentIsForced()
{
	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery("Observation", "42", {"category":"laboratory"}, .reason)
	Do $$$AssertNotEquals(query, "", "valid request accepted: "_reason)
	Do $$$AssertTrue(query [ "patient=Patient/42", "compartment parameter is present")
	Do $$$AssertTrue(query [ "category=laboratory", "caller parameter is preserved")
}

Method TestCompartmentCannotBeOverridden()
{
	// A caller trying to point the search at a different patient.
	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery("Observation", "42", {"patient":"Patient/99"}, .reason)
	Do $$$AssertTrue(query [ "patient=Patient/42", "server-set compartment wins")
	Do $$$AssertNotTrue(query [ "Patient/99", "caller-supplied compartment is dropped")
}

Method TestParameterAllowlist()
{
	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery("Observation", "42", {"_include":"Observation:subject"}, .reason)
	Do $$$AssertEquals(query, "", "_include is rejected")
	Do $$$AssertTrue(reason [ "_include", "refusal names the offending parameter")

	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery("Observation", "42", {"_revinclude":"Provenance:target"}, .reason)
	Do $$$AssertEquals(query, "", "_revinclude is rejected")

	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery("Condition", "42", {"_has:Observation:patient:code":"1234"}, .reason)
	Do $$$AssertEquals(query, "", "_has chaining is rejected")
}

Method TestUnknownResourceTypeIsRejected()
{
	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery("Practitioner", "42", {}, .reason)
	Do $$$AssertEquals(query, "", "unexposed resource type is rejected")
	Do $$$AssertTrue(reason [ "Practitioner", "refusal names the resource type")
	Do $$$AssertTrue(reason [ "Allowed", "refusal lists what is allowed")
}

Method TestMissingPatientIsRejected()
{
	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery("Observation", "", {}, .reason)
	Do $$$AssertEquals(query, "", "search without a patient is rejected")
}

Method TestCountIsClamped()
{
	Set max = ##class(GovernedFHIR.Core.Guard).#MAXROWS
	Do $$$AssertEquals(##class(GovernedFHIR.Core.Guard).ClampCount(100000), max, "oversized _count is clamped")
	Do $$$AssertEquals(##class(GovernedFHIR.Core.Guard).ClampCount(0), max, "zero _count falls back to the cap")
	Do $$$AssertEquals(##class(GovernedFHIR.Core.Guard).ClampCount(5), 5, "reasonable _count is preserved")

	Set query = ##class(GovernedFHIR.Core.Guard).BuildPatientQuery("Observation", "42", {"_count":99999}, .reason)
	Do $$$AssertTrue(query [ ("_count="_max), "clamped _count reaches the query")
}

Method TestDenialIsRecognisedInThePayload()
{
	Set denial = ##class(GovernedFHIR.Core.Guard).Deny("_include is not allowed")
	Do $$$AssertEquals(##class(GovernedFHIR.AI.Policy.AuditLog).DeniedReason(denial), "_include is not allowed", "a Guard denial is read out of the payload")

	Set capped = ##class(GovernedFHIR.Core.Guard).CapPayload($Justify("", ##class(GovernedFHIR.Core.Guard).#MAXCHARS + 10), .t)
	Do $$$AssertNotEquals(##class(GovernedFHIR.AI.Policy.AuditLog).DeniedReason(capped), "", "an oversized result counts as a refusal too")

	Do $$$AssertEquals(##class(GovernedFHIR.AI.Policy.AuditLog).DeniedReason({"returned":0, "items":[]}.%ToJSON()), "", "an empty but successful result is not a denial")
	Do $$$AssertEquals(##class(GovernedFHIR.AI.Policy.AuditLog).DeniedReason(""), "", "a missing result is not a denial")
	Do $$$AssertEquals(##class(GovernedFHIR.AI.Policy.AuditLog).DeniedReason("not json at all"), "", "unparseable result is not a denial")

	Set wrapped = {"result": (denial)}.%ToJSON()
	Do $$$AssertEquals(##class(GovernedFHIR.AI.Policy.AuditLog).DeniedReason(wrapped), "_include is not allowed", "a denial survives one layer of wrapping")
	Do $$$AssertEquals(##class(GovernedFHIR.AI.Policy.AuditLog).DeniedReason({"content": (wrapped)}.%ToJSON()), "_include is not allowed", "and two")
}

Method TestAnswerWrapping()
{
	Set text = "HbA1c 6.21 % on 2025-10-25 (Observation/3d852e71-d854-5968-602f-d5c6fdcfd040) and glucose 97.3 mg/dL"
	Set wrapped = ##class(GovernedFHIR.AI.Agent).Wrap(text, 40)
	Do $$$AssertTrue($Length(wrapped, $Char(10)) > 1, "a long line is broken up")
	For i = 1:1:$Length(wrapped, $Char(10)) {
		Set line = $Piece(wrapped, $Char(10), i)
		Do $$$AssertTrue($Length(line) <= 40 || ($Length(line, " ") = 1), "only an unbreakable token may exceed the width: "_line)
	}
	Do $$$AssertEquals($Translate(wrapped, $Char(10), " "), text, "no word is lost or split")

	Do $$$AssertEquals(##class(GovernedFHIR.AI.Agent).Wrap("  - Anemia (disorder)", 40), "  - Anemia (disorder)", "a short line and its indent survive untouched")
	Do $$$AssertNotTrue(##class(GovernedFHIR.AI.Agent).Wrap("a"_$Char(9)_"b") [ $Char(9), "tabs are removed - they are what the terminal mangles")

	Set typographic = "Pain severity 1 (0"_$Char(8211)_"10) "_$Char(8212)_" see "_$Char(8220)_"notes"_$Char(8221)_$Char(8230)
	Set folded = ##class(GovernedFHIR.AI.Agent).Wrap(typographic)
	Do $$$AssertEquals(folded, "Pain severity 1 (0-10) - see ""notes""...", "dashes, curly quotes and the ellipsis are folded to ASCII")
}

Method TestProjectionNamesItsResourceType()
{
	For type = "Condition","Observation","MedicationRequest","AllergyIntolerance","Encounter","Immunization" {
		Set out = ##class(GovernedFHIR.Core.Projection).ByType({"resourceType":(type), "id":"x1"})
		Do $$$AssertEquals(out.resourceType, type, type_" projects its own resource type")
		Do $$$AssertEquals(out.id, "x1", type_" keeps its id")
	}
}

Method TestBloodPressureComponents()
{
	Set bp = {"resourceType":"Observation","id":"bp1","code":{"text":"Blood pressure panel"},"component":[
		{"code":{"text":"Systolic blood pressure"},"valueQuantity":{"value":128,"unit":"mm[Hg]"}},
		{"code":{"text":"Diastolic blood pressure"},"valueQuantity":{"value":81,"unit":"mm[Hg]"}}]}
	Set out = ##class(GovernedFHIR.Core.Projection).ByType(bp)
	Do $$$AssertEquals(out.components.%Size(), 2, "both components survive")
	Do $$$AssertEquals(out.components.%Get(0).value, 128, "systolic value survives")
	Do $$$AssertEquals(out.components.%Get(1).unit, "mm[Hg]", "unit survives")

	Set plain = ##class(GovernedFHIR.Core.Projection).ByType({"resourceType":"Observation","id":"o1","valueQuantity":{"value":6.21,"unit":"%"}})
	Do $$$AssertNotTrue(plain.%IsDefined("components"), "a single-valued Observation gains no empty components array")
	Do $$$AssertEquals(plain.value, 6.21, "a single-valued Observation is unaffected")
}

Method TestSummaryKeepsOnlyTheLatestOfEachVital()
{
	Set items = [
		{"id":"a","code":"Heart rate","value":89,"effective":"2025-10-25"},
		{"id":"b","code":"Body Weight","value":76.3,"effective":"2025-10-25"},
		{"id":"c","code":"Heart rate","value":80,"effective":"2024-10-19"},
		{"id":"d","code":"Body Weight","value":74.1,"effective":"2024-10-19"}]
	Set out = ##class(GovernedFHIR.AI.Tools).LatestByCode(items)
	Do $$$AssertEquals(out.%Size(), 2, "one row per measurement")
	Do $$$AssertEquals(out.%Get(0).id, "a", "the newest heart rate is the one kept")
	Do $$$AssertEquals(out.%Get(1).id, "b", "the newest weight is the one kept")

	Do $$$AssertEquals(##class(GovernedFHIR.AI.Tools).LatestByCode([]).%Size(), 0, "an empty section stays empty")
}

Method TestPayloadCap()
{
	Set small = "{""ok"":true}"
	Do $$$AssertEquals(##class(GovernedFHIR.Core.Guard).CapPayload(small, .t), small, "small payload passes through")
	Do $$$AssertNotTrue(t, "small payload is not flagged truncated")

	Set big = $Justify("", ##class(GovernedFHIR.Core.Guard).#MAXCHARS + 10)
	Set capped = ##class(GovernedFHIR.Core.Guard).CapPayload(big, .t)
	Do $$$AssertTrue(t, "oversized payload is flagged truncated")
	Do $$$AssertTrue(capped [ "result_too_large", "oversized payload is replaced by an actionable envelope")
}

}
