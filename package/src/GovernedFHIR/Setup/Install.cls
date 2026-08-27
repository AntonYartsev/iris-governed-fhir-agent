Include %occStatus

/// FHIR R4 endpoint plus the bundled Synthea dataset
/// The package install does not call this - iris.script does
/// Safe to re-run
Class GovernedFHIR.Setup.Install Extends %RegisteredObject
{

Parameter APPKEY As STRING = "/fhir/r4";

Parameter STRATEGY As STRING = "HS.FHIRServer.Storage.Json.InteractionsStrategy";

Parameter PACKAGE As STRING = "hl7.fhir.r4.core@4.0.1";

/// Overridden by FHIR_DATA_DIR.
Parameter DATADIR As STRING = "/home/irisowner/dev/data/synthea";

ClassMethod Run() As %Status
{
	$$$QuitOnError(..InstallEndpoint())
	$$$QuitOnError(..LoadData())
	Do ##class(GovernedFHIR.Audit.Entry).EnsureEvent()
	Return $$$OK
}

ClassMethod InstallEndpoint() As %Status
{
	Try {
		If ##class(HS.FHIRServer.Installer).CSPAppExists(..#APPKEY) {
			Write "FHIR endpoint ", ..#APPKEY, " already installed", !
			Return ..RelaxAuth()
		}

		Do ##class(HS.FHIRServer.Installer).InstallNamespace()
		Do ##class(HS.FHIRServer.Installer).InstallInstance(..#APPKEY, ..#STRATEGY, ..#PACKAGE)
		Write "FHIR endpoint installed - ", ..#APPKEY, !
		Return ..RelaxAuth()
	} Catch ex {
		Return $$$ERROR($$$GeneralError, "FHIR endpoint install failed: "_ex.DisplayString())
	}
}

/// Unauthenticated calls and verbose errors
ClassMethod RelaxAuth() As %Status
{
	Try {
		Set strategy = ##class(HS.FHIRServer.API.InteractionsStrategy).GetStrategyForEndpoint(..#APPKEY)
		Set config = strategy.GetServiceConfigData()
		Set config.DebugMode = 4
		Do config.Update()
	} Catch ex {
		Write "Error set DebugMode: ", ex.DisplayString(), !
	}
	Return $$$OK
}

ClassMethod LoadData() As %Status
{
	Set dir = $System.Util.GetEnviron("FHIR_DATA_DIR")
	If dir = "" Set dir = ..#DATADIR

	If '##class(%File).DirectoryExists(dir) {
		Write "No data directory at ", dir, " - skipping", !
		Return $$$OK
	}

	If ..PatientCount() > 0 {
		Write "FHIR repository already populated - skipping", !
		Return $$$OK
	}

	Write "Loading FHIR data from ", dir, " ..", !
	Set sc = ##class(HS.FHIRServer.Tools.DataLoader).SubmitResourceFiles(dir, "FHIRServer", ..#APPKEY)
	If $$$ISERR(sc) {
		Write "Data load says: ", $System.Status.GetErrorText(sc), !
		Return $$$OK
	}
	Write "Loaded ", ..PatientCount(), " patients", !
	Return $$$OK
}

ClassMethod PatientCount() As %Integer
{
	Try {
		Set bundle = ##class(GovernedFHIR.Core.Repo).Search("Patient", "_summary=count", .outcome)
		If outcome '= "" Return 0
		Return +bundle.total
	} Catch ex {
		Return 0
	}
}

ClassMethod Doctor() As %Status
{
	Write !, "iris-governed-fhir-agent environment check info:", !
	Write "Namespace          : ", $Namespace, !
	Write "FHIR endpoint      : ", $Select(##class(HS.FHIRServer.Installer).CSPAppExists(..#APPKEY): "present", 1: "MISSING"), !
	Write "FHIR responds      : ", $Select(##class(GovernedFHIR.Core.Repo).IsReady(): "yes", 1: "NO"), !
	Write "Patients loaded    : ", ..PatientCount(), !
	Write "OPENAI_API_KEY     : ", $Select($System.Util.GetEnviron("OPENAI_API_KEY") '= "": "set", 1: "NOT SET"), !
	Write "OPENAI_BASE_URL    : ", $Select($System.Util.GetEnviron("OPENAI_BASE_URL") '= "": $System.Util.GetEnviron("OPENAI_BASE_URL"), 1: "(default)"), !
	Write "Audited tool calls : ", ..AuditCount(), !
	Return $$$OK
}

ClassMethod AuditCount() As %Integer
{
	Try {
		Set rs = ##class(%SQL.Statement).%ExecDirect(, "SELECT COUNT(*) FROM GovernedFHIR_Audit.Entry")
		If rs.%Next() Return rs.%GetData(1)
	} Catch ex {
	}
	Return 0
}

}
