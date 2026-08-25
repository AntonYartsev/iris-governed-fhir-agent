Include (%AI, %occStatus)

/// A second check in front of every tool call
/// The duplication is deliberate:
/// Tools are reachable from ObjectScript, from an agent and from any MCP client, and this sits on the ToolManager and sees all three.
/// Add a fourth tool, forget the Guard call and a scopeless request still gets denied
Class GovernedFHIR.AI.Policy.Compartment Extends %AI.Policy.Authorization
{

/// Tool, that legitimately runs without a patient scope
Parameter RESOLUTIONTOOL As STRING = "FindPatient";

Method %CanExecute(
	tool As %String,
	call As %DynamicObject,
	metadata As %DynamicObject) As %Status
{
	Set name = call.name

	If $Piece(name, "_", *) = ..#RESOLUTIONTOOL Return $$$OK

	Set patientId = ""
	If $IsObject($Get(call)), $IsObject(call.arguments) {
		Set patientId = call.arguments.%Get("patientId", "")
	}

	If '##class(GovernedFHIR.Core.Guard).IsPatientIdValid(patientId) {
		Return ..Deny(call, name, patientId, "Tool '"_name_"' requires a valid patientId. Resolve the patient first; patient scope is not optional.")
	}

	// The allowlist again, outside the tool body.
	Set resourceType = ""
	If $IsObject(call.arguments) {
		Set resourceType = call.arguments.%Get("resourceType", "")
	}
	If resourceType '= "" {
		If '##class(GovernedFHIR.Core.Guard).IsResourceAllowed(resourceType) {
			Return ..Deny(call, name, patientId, "Resource type '"_resourceType_"' is not exposed by this toolset.")
		}
	}

	Return $$$OK
}

/// The ToolManager stops at a failed %CanExecute and never reaches the audit policy
/// So a denial would leave no trace - and a denied read is exactly what an audit trail is for
/// Hence logging it here
Method Deny(
	call As %DynamicObject,
	name As %String,
	patientId As %String,
	reason As %String) As %Status [ Private ]
{
	Try {
		Set args = $Select($IsObject(call.arguments): call.arguments.%ToJSON(), 1: "")
		Do ##class(GovernedFHIR.Audit.Entry).Log(name, args, patientId, 0, 0, 0, reason)
	} Catch ex {
		// Auditing must never take down the refusal it is recording!
	}
	Return $$$ERROR($$$GeneralError, reason)
}

}
