/// FHIR access, no AI Hub dependency
/// When EAP API moves - layers above break and this one keeps working
Class GovernedFHIR.Core.Repo Extends %RegisteredObject
{

Parameter APPKEY As STRING = "/fhir/r4";

/// GET internal FHIR service
/// On failure - Outcome carries the reason and the payload may be in OperationOutcome
ClassMethod Get(
	path As %String,
	Output outcome As %String) As %DynamicObject
{
	Set outcome = ""
	Try {
		Set service = ##class(HS.FHIRServer.Service).EnsureInstance(..#APPKEY)
		Set request = ##class(HS.FHIRServer.API.Data.Request).%New()
		Set request.RequestMethod = "GET"
		// This build answers 404 when query string rides along on RequestPath - it takes whole thing as a path! They go in separate properties
		Set request.RequestPath = $Piece(path, "?", 1)
		Set request.QueryString = $Piece(path, "?", 2, *)
		Do service.DispatchRequest(request, .response)
	} Catch ex {
		Set outcome = "FHIR dispatch failed: "_ex.DisplayString()
		Return {}
	}

	If '$IsObject($Get(response)) {
		Set outcome = "empty response from FHIR service"
		Return {}
	}

	Set code = $Piece(response.Status, " ", 1)
	If (+code '= 200) {
		Set outcome = "FHIR status "_response.Status
	}
	Return response.Json
}

/// Query must already be through GovernedFHIR.Core.Guard
ClassMethod Search(
	resourceType As %String,
	query As %String = "",
	Output outcome As %String) As %DynamicObject
{
	Set path = "/"_resourceType
	If query '= "" Set path = path_"?"_query
	Return ..Get(path, .outcome)
}

ClassMethod Read(
	resourceType As %String,
	id As %String,
	Output outcome As %String) As %DynamicObject
{
	Return ..Get("/"_resourceType_"/"_id, .outcome)
}

/// Resources out of a searchset Bundle
/// Non-bundles - empty array
ClassMethod Entries(bundle As %DynamicObject) As %DynamicArray
{
	Set out = []
	If '$IsObject($Get(bundle)) Return out
	If 'bundle.%IsDefined("entry") Return out
	Set iter = bundle.entry.%GetIterator()
	While iter.%GetNext(.i, .entry) {
		If $IsObject(entry), entry.%IsDefined("resource") {
			Do out.%Push(entry.resource)
		}
	}
	Return out
}

ClassMethod IsReady() As %Boolean
{
	Do ..Get("/metadata", .outcome)
	Return (outcome = "")
}

}
