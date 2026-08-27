/// Just simply one row per tool call, so "what did the model actually read?" has an answer after the fact
/// SELECT Ts, ToolName, PatientId, Allowed, DurationMs, ErrorText FROM GovernedFHIR_Audit.Entry ORDER BY ID DESC
Class GovernedFHIR.Audit.Entry Extends %Persistent
{

Property Ts As %TimeStamp [ InitialExpression = {$ZDateTime($ZTimeStamp, 3, 1)} ];

Property ToolName As %String(MAXLEN = 128);

/// Capped - a real deployment would redact here
Property Arguments As %String(MAXLEN = 2000);

Property PatientId As %String(MAXLEN = 64);

Property Allowed As %Boolean [ InitialExpression = 1 ];

Property DurationMs As %Integer;

Property ResultChars As %Integer;

Property ErrorText As %String(MAXLEN = 1000);

/// Agent or mcp
Property Channel As %String(MAXLEN = 32);

Parameter AUDITSOURCE As STRING = "GovernedFHIR";

Parameter AUDITTYPE As STRING = "ToolCall";

Parameter AUDITNAME As STRING = "Denied";

Index ByTs On Ts;

Index ByPatient On PatientId;

/// MCP service dispatches through CSP, so %request is an object only on that path
/// Agent runs in plain process
ClassMethod Channel() As %String
{
	Return $Select($IsObject($Get(%request)): "mcp", 1: "agent")
}

ClassMethod Log(
	toolName As %String,
	arguments As %String,
	patientId As %String,
	allowed As %Boolean,
	durationMs As %Integer = 0,
	resultChars As %Integer = 0,
	errorText As %String = "",
	channel As %String = "") As %Status
{
	If channel = "" Set channel = ..Channel()
	Set entry = ..%New()
	Set entry.ToolName = $Extract(toolName, 1, 128)
	Set entry.Arguments = $Extract(arguments, 1, 2000)
	Set entry.PatientId = $Extract(patientId, 1, 64)
	Set entry.Allowed = allowed
	Set entry.DurationMs = durationMs
	Set entry.ResultChars = resultChars
	Set entry.ErrorText = $Extract(errorText, 1, 1000)
	Set entry.Channel = channel
	Set sc = entry.%Save()
	// A refusal is the row an audit trail exists for, so it goes into the IRIS audit
	// database too - the one a security team already watches (caps at 128)
	If 'allowed Do $System.Security.Audit(..#AUDITSOURCE, ..#AUDITTYPE, ..#AUDITNAME, arguments, $Extract(toolName_" denied: "_errorText, 1, 128))
	Return sc
}

/// $System.Security.Audit needs the audit subsystem on and the event defined, both in %SYS
ClassMethod EnsureEvent()
{
	New $Namespace
	Set $Namespace = "%SYS"
	Try {
		Do ##class(Security.System).Get(, .props)
		If $Get(props("AuditEnabled")) '= 1 {
			Set props("AuditEnabled") = 1
			Do ##class(Security.System).Modify(, .props)
		}
		If '##class(Security.Events).Exists(..#AUDITSOURCE, ..#AUDITTYPE, ..#AUDITNAME) {
			Do ##class(Security.Events).Create(..#AUDITSOURCE, ..#AUDITTYPE, ..#AUDITNAME, "Denied GovernedFHIR tool call")
		}
		Write "IRIS audit event ready - ", ..#AUDITSOURCE, "/", ..#AUDITTYPE, "/", ..#AUDITNAME, !
	} Catch ex {
		Write "IRIS audit setup skipped: ", ex.DisplayString(), !
	}
}

Storage Default
{
<Data name="EntryDefaultData">
<Value name="1">
<Value>%%CLASSNAME</Value>
</Value>
<Value name="2">
<Value>Ts</Value>
</Value>
<Value name="3">
<Value>ToolName</Value>
</Value>
<Value name="4">
<Value>Arguments</Value>
</Value>
<Value name="5">
<Value>PatientId</Value>
</Value>
<Value name="6">
<Value>Allowed</Value>
</Value>
<Value name="7">
<Value>DurationMs</Value>
</Value>
<Value name="8">
<Value>ResultChars</Value>
</Value>
<Value name="9">
<Value>ErrorText</Value>
</Value>
<Value name="10">
<Value>Channel</Value>
</Value>
</Data>
<DataLocation>^GovernedFHIR.Audit.EntryD</DataLocation>
<DefaultData>EntryDefaultData</DefaultData>
<IdLocation>^GovernedFHIR.Audit.EntryD</IdLocation>
<IndexLocation>^GovernedFHIR.Audit.EntryI</IndexLocation>
<StreamLocation>^GovernedFHIR.Audit.EntryS</StreamLocation>
<Type>%Storage.Persistent</Type>
}

}
