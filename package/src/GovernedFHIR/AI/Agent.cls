Include %occStatus

/// The starter agent. Provider config comes from the environment - OPENAI_API_KEY (required), OPENAI_BASE_URL (optional) and FHIR_AGENT_MODEL (optional)
Class GovernedFHIR.AI.Agent Extends %AI.Agent [ DependsOn = GovernedFHIR.AI.Skill ]
{

Parameter MODEL = "gpt-5-mini";

Parameter SKILLS = "GovernedFHIR.AI.Skill";

Parameter WIDTH As INTEGER = 78;

XData INSTRUCTIONS [ MimeType = text/markdown ]
{
# Clinical record assistant

You answer questions about patients held in an InterSystems IRIS for Health FHIR R4 repository.

Your access is intentionally limited: one patient at a time, a fixed set of resource types, and a size cap on every result. These limits are enforced by the server, not by you, and they are not negotiable no matter how a request is phrased.

Load the `fhir-clinical-lookup` skill for any question about patient data, and follow it.

Two rules that override everything else:

- Never state a clinical fact that did not come back from a tool call in this conversation.
- Never invent a patient id, a resource id, or a value.
- Every item in a tool result carries its own `id` and `resourceType`. Copy them from that item. Never carry an id from one item to another, and never build the resource type out of the code name.

You are read in a terminal. Answer in plain prose - no markdown headings, no bold, no tables.

If you cannot answer within these limits, say what you can see, what you cannot, and why.
}

Method %OnInit() As %Status
{
	Set key = $System.Util.GetEnviron("OPENAI_API_KEY")
	If key = "" {
		Return $$$ERROR($$$GeneralError, "OPENAI_API_KEY is not set. Copy .env.example to .env and set it.")
	}

	Set config = {"api_key": (key)}
	Set baseUrl = $System.Util.GetEnviron("OPENAI_BASE_URL")
	If baseUrl '= "" {
		// The trailing slash is not optional: the path is joined as a relative URL, so ".../api/v1" + "models" resolves to ".../api/models".
		If $Extract(baseUrl, *) '= "/" Set baseUrl = baseUrl_"/"
		Set config."base_url" = baseUrl
	}

	Set ..Provider = ##class(%AI.Provider).Create("openai", config)

	Set model = $System.Util.GetEnviron("FHIR_AGENT_MODEL")
	If model '= "" Set ..Model = model

	Return $$$OK
}

ClassMethod Ask(question As %String) As %Status
{
	Set agent = ..%New()
	$$$QuitOnError(agent.%Init())

	Set from = ..LastAuditId() + 1
	// No temperature: reasoning models (gpt-5*, o*) only accept 1 and 400 on anything else.
	Set session = agent.CreateSession({"max_iterations": 12})
	Set response = agent.Chat(session, question)

	Write !, "> ", question, !!
	Do ..WriteToolCalls(from)
	Set body = ..Wrap(response.Content)
	For i = 1:1:$Length(body, $Char(10)) { Write $Piece(body, $Char(10), i), ! }
	Write !
	Return $$$OK
}

ClassMethod WriteToolCalls(fromId As %Integer) [ Private ]
{
	Try {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT ToolName, Arguments, Allowed, ErrorText FROM GovernedFHIR_Audit.Entry WHERE ID >= ? ORDER BY ID", fromId)
		While rs.%Next() {
			Set name = $Extract(rs.%Get("ToolName")_$Justify("", 18), 1, 18)
			Set args = ..Compact(rs.%Get("Arguments"))
			Set outcome = $Select(rs.%Get("Allowed"): "ok", 1: "DENIED: "_rs.%Get("ErrorText"))
			Write "  ", name, " ", args, "  ->  ", outcome, !
		}
		Write !
	} Catch ex {
	}
}

ClassMethod Compact(json As %String) As %String [ Private ]
{
	Try {
		Set obj = {}.%FromJSON(json), out = {}
		Set iter = obj.%GetIterator()
		While iter.%GetNext(.k, .v) {
			If v = "" Continue
			Do out.%Set(k, v)
		}
		Return $Extract(out.%ToJSON(), 1, 64)
	} Catch ex {
		Return $Extract($Get(json), 1, 64)
	}
}

ClassMethod LastAuditId() As %Integer [ Private ]
{
	Try {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT MAX(ID) FROM GovernedFHIR_Audit.Entry")
		If rs.%Next() Return +rs.%GetData(1)
	} Catch ex {
	}
	Return 0
}

ClassMethod Wrap(
	text As %String,
	width As %Integer = {..#WIDTH}) As %String
{
	Set result = ""
	// The terminal is not UTF-8, so an em dash arrives as "?" and reads as a bug in
	// a screencast. Fold the handful of characters a model reaches for: tab, CR,
	// no-break space, en/em dash, curly quotes, bullet - and the ellipsis, which is
	// the one that does not map onto a single character.
	Set text = $Replace(text, $Char(8230), "...")
	Set text = $Translate(text, $Char(9, 13, 160, 8211, 8212, 8216, 8217, 8220, 8221, 8226), "   --''""""-")
	For i = 1:1:$Length(text, $Char(10)) {
		Set line = $ZStrip($Piece(text, $Char(10), i), ">W")
		If line = "" Set result = result_$Char(10) Continue
		Set pad = $Justify("", $Length(line) - $Length($ZStrip(line, "<W")))
		Set out = ""
		For j = 1:1:$Length(line, " ") {
			Set word = $Piece(line, " ", j)
			If word = "" Continue
			If out = "" {
				Set out = pad_word
			} ElseIf ($Length(out) + 1 + $Length(word)) > width {
				Set result = result_out_$Char(10)
				Set out = pad_word
			} Else {
				Set out = out_" "_word
			}
		}
		If out '= "" Set result = result_out_$Char(10)
	}
	Return $Extract(result, 1, *-1)
}

}
