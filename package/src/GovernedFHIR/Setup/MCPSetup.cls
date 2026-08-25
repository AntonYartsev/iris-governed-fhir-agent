Include %occStatus

/// The MCP web application. Like Install, called by iris.script
Class GovernedFHIR.Setup.MCPSetup Extends %RegisteredObject
{

Parameter APPPATH As STRING = "/mcp/governed-fhir";

ClassMethod Run(namespace As %String = {$Namespace}) As %Status
{
	New $Namespace
	Set $Namespace = "%SYS"

	Do ##class(Security.Applications).Delete(..#APPPATH)

	Kill props
	Set props("DispatchClass") = "GovernedFHIR.MCP.Service"
	// Unauthenticated - synthetic data in a demo image
	Set props("AutheEnabled") = 64
	Set props("Type") = 18
	Set props("NameSpace") = namespace
	Set props("MatchRoles") = ":%All"

	Set sc = ##class(Security.Applications).Create(..#APPPATH, .props)
	If $$$ISERR(sc) {
		Write "MCP registration failed: ", $System.Status.GetErrorText(sc), !
		Return sc
	}
	Write "MCP registered at ", ..#APPPATH, !
	Return $$$OK
}

}
