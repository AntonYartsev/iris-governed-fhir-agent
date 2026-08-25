/// Synthea Observation lines of JSON, most of it provenance the model cannot use
/// These projections keep the id, so every fact stays checkable
Class GovernedFHIR.Core.Projection Extends %RegisteredObject
{

/// Patient -> {id, name, gender, birthDate, identifiers}
ClassMethod Patient(res As %DynamicObject) As %DynamicObject
{
	Set out = {}
	Set out.id = res.id
	Set out.name = ..HumanName(res)
	Set out.gender = res.gender
	Set out.birthDate = res.birthDate
	Set ids = []
	If $IsObject(res), res.%IsDefined("identifier") {
		Set iter = res.identifier.%GetIterator()
		While iter.%GetNext(.i, .ident) {
			Set system = ident.system
			Set value = ident.value
			If value = "" Continue
			Do ids.%Push({"system":(system), "value":(value)})
		}
	}
	Set out.identifiers = ids
	Return out
}

/// "Given Family"
ClassMethod HumanName(res As %DynamicObject) As %String
{
	If '$IsObject($Get(res)) Return ""
	If 'res.%IsDefined("name") Return ""
	Set iter = res.name.%GetIterator()
	While iter.%GetNext(.i, .n) {
		Set family = n.family
		Set given = ""
		If $IsObject(n), n.%IsDefined("given") {
			Set giter = n.given.%GetIterator()
			While giter.%GetNext(.j, .g) {
				Set given = given _ $Select(given = "": "", 1: " ") _ g
			}
		}
		If (family '= "") || (given '= "") {
			Return $ZStrip(given _ " " _ family, "<>W")
		}
	}
	Return ""
}

/// Condition -> {id, code, clinicalStatus, onset}
ClassMethod Condition(res As %DynamicObject) As %DynamicObject
{
	Return {
		"id":             (res.id),
		"code":           (..CodeText(res.code)),
		"clinicalStatus": (..CodeText(res.clinicalStatus)),
		"onset":          (res.onsetDateTime)
	}
}

/// Observation -> {id, code, value, unit, effective, status}
ClassMethod Observation(res As %DynamicObject) As %DynamicObject
{
	Set value = "", unit = "", components = ""
	If $IsObject($Get(res)), res.%IsDefined("valueQuantity") {
		Set value = res.valueQuantity.value
		Set unit = res.valueQuantity.unit
	} ElseIf $IsObject($Get(res)), res.%IsDefined("valueCodeableConcept") {
		Set value = ..CodeText(res.valueCodeableConcept)
	} ElseIf $IsObject($Get(res)), res.%IsDefined("valueString") {
		Set value = res.valueString
	} ElseIf $IsObject($Get(res)), res.%IsDefined("component") {
		Set components = []
		Set iter = res.component.%GetIterator()
		While iter.%GetNext(.i, .c) {
			Set q = c.valueQuantity
			Do components.%Push({
				"code":  (..CodeText(c.code)),
				"value": ($Select($IsObject(q): q.value, 1: "")),
				"unit":  ($Select($IsObject(q): q.unit, 1: ""))
			})
		}
	}
	Set out = {
		"id":        (res.id),
		"code":      (..CodeText(res.code)),
		"value":     (value),
		"unit":      (unit),
		"effective": (res.effectiveDateTime),
		"status":    (res.status)
	}
	If $IsObject(components) Set out.components = components
	Return out
}

/// MedicationRequest -> {id, medication, status, intent, authoredOn}
ClassMethod MedicationRequest(res As %DynamicObject) As %DynamicObject
{
	Set med = ""
	If $IsObject($Get(res)), res.%IsDefined("medicationCodeableConcept") {
		Set med = ..CodeText(res.medicationCodeableConcept)
	} ElseIf $IsObject($Get(res)), res.%IsDefined("medicationReference") {
		Set med = res.medicationReference.display
	}
	Return {
		"id":         (res.id),
		"medication": (med),
		"status":     (res.status),
		"intent":     (res.intent),
		"authoredOn": (res.authoredOn)
	}
}

/// AllergyIntolerance -> {id, substance, clinicalStatus, criticality}
ClassMethod Allergy(res As %DynamicObject) As %DynamicObject
{
	Return {
		"id":             (res.id),
		"substance":      (..CodeText(res.code)),
		"clinicalStatus": (..CodeText(res.clinicalStatus)),
		"criticality":    (res.criticality)
	}
}

/// Fallback for types without a dedicated projection
ClassMethod Generic(res As %DynamicObject) As %DynamicObject
{
	Return {
		"id":           (res.id),
		"resourceType": (res.resourceType),
		"status":       (res.status),
		"code":         (..AnyCode(res)),
		"date":         (..AnyDate(res))
	}
}

/// FHIR names the clinical code differently per resource type - Encounter has
/// no code at all, only type[], and Immunization calls it vaccineCode
ClassMethod AnyCode(res As %DynamicObject) As %String
{
	If '$IsObject($Get(res)) Return ""
	Set text = ..CodeText(res.code)
	If text = "" Set text = ..CodeText(res.vaccineCode)
	If text = "", res.%IsDefined("type"), res.type.%Size() > 0 {
		Set text = ..CodeText(res.type.%Get(0))
	}
	Return text
}

/// Same story for the date. Period-shaped resources report their start
ClassMethod AnyDate(res As %DynamicObject) As %String
{
	If '$IsObject($Get(res)) Return ""
	If res.%IsDefined("effectiveDateTime") Return res.effectiveDateTime
	If res.%IsDefined("occurrenceDateTime") Return res.occurrenceDateTime
	If res.%IsDefined("performedDateTime") Return res.performedDateTime
	If res.%IsDefined("performedPeriod") Return res.performedPeriod.start
	If res.%IsDefined("period") Return res.period.start
	Return ""
}

ClassMethod ByType(res As %DynamicObject) As %DynamicObject
{
	Set out = $Case(res.resourceType,
		"Patient":            ..Patient(res),
		"Condition":          ..Condition(res),
		"Observation":        ..Observation(res),
		"MedicationRequest":  ..MedicationRequest(res),
		"AllergyIntolerance": ..Allergy(res),
		:                     ..Generic(res))

	Set out.resourceType = res.resourceType
	Return out
}

/// Every resource in a searchset Bundle, projected
ClassMethod Bundle(bundle As %DynamicObject) As %DynamicArray
{
	Set items = []
	Set iter = ##class(GovernedFHIR.Core.Repo).Entries(bundle).%GetIterator()
	While iter.%GetNext(.i, .res) {
		Do items.%Push(..ByType(res))
	}
	Return items
}

/// CodeableConcept -> best available label
ClassMethod CodeText(cc As %DynamicObject) As %String
{
	If '$IsObject($Get(cc)) Return ""
	If cc.%IsDefined("text"), cc.text '= "" Return cc.text
	If cc.%IsDefined("coding") {
		Set iter = cc.coding.%GetIterator()
		While iter.%GetNext(.i, .coding) {
			If coding.display '= "" Return coding.display
			If coding.code '= "" Return coding.code
		}
	}
	Return ""
}

}
