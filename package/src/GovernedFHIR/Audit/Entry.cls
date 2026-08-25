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
	Return entry.%Save()
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
