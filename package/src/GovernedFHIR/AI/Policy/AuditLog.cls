Include (%AI, %occStatus)

/// One row per tool call, as AGENTS.md recommends - %AI.Policy.ConsoleAudit breaks MCP
/// DeniedReason() below is the part that is not in the docs
Class GovernedFHIR.AI.Policy.AuditLog Extends %AI.Policy.Audit
{

Method %LogExecution(
	call As %DynamicObject,
	metadata As %DynamicObject,
	result As %DynamicObject,
	duration As %Integer,
	status As %Status) As %Status
{
	Try {
		Set name = call.name
		Set args = ""
		Set patientId = ""
		// The two hooks disagree on shape:
		// 1. %CanExecute gets arguments as an object,
		// 2. %LogExecution as the raw JSON string
		// Take either, or the row loses the one detail it exists for
		Set argsObj = ""
		If $IsObject($Get(call)) {
			Set raw = call.arguments
			If $IsObject(raw) {
				Set argsObj = raw
			} ElseIf raw '= "" {
				Try { Set argsObj = {}.%FromJSON(raw) } Catch { Set argsObj = "" }
			}
		}
		If $IsObject(argsObj) {
			Set args = argsObj.%ToJSON()
			Set patientId = argsObj.%Get("patientId", "")
		}

		Set resultChars = 0
		If $IsObject($Get(result)) {
			Set resultChars = $Length(result.%ToJSON())
		} ElseIf $Data(result) {
			Set resultChars = $Length(result)
		}

		Set allowed = $$$ISOK(status)
		Set errorText = ""
		If 'allowed {
			Set errorText = $System.Status.GetErrorText(status)
		} Else {
			Set errorText = ..DeniedReason($Get(result))
			If errorText '= "" Set allowed = 0
		}

		Do ##class(GovernedFHIR.Audit.Entry).Log(name, args, patientId, allowed, duration, resultChars, errorText)
	} Catch ex {
		// Auditing must never take down the tool call it is auditing!
	}
	Return $$$OK
}

ClassMethod DeniedReason(result) As %String
{
	Try {
		Set raw = $Select($IsObject($Get(result)): result.%ToJSON(), 1: $Get(result))
		If raw = "" Return ""

		For i = 1:1:5 {
			If raw '[ "\" Quit
			Set raw = $Replace($Replace(raw, "\""", """"), "\\", "\")
		}
		If (raw '[ """error"":""denied""") && (raw '[ """error"":""result_too_large""") Return ""

		Set at = $Find(raw, """message"":""")
		If at = 0 Return "denied"
		Return $Piece($Extract(raw, at, *), """", 1)
	} Catch ex {
		Return ""
	}
}

}
