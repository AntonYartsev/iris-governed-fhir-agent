Class GovernedFHIR.AI.ToolSet Extends %AI.ToolSet [ DependsOn = (GovernedFHIR.AI.Tools, GovernedFHIR.AI.Policy.Compartment, GovernedFHIR.AI.Policy.AuditLog) ]
{

XData Definition [ MimeType = application/xml ]
{
<ToolSet Name="GovernedFHIR">
  <Description>Read-only, patient-scoped FHIR R4 tools over InterSystems IRIS for Health. Every call is limited to one patient compartment, restricted to an allowlist of resource types and search parameters, size-capped, and audited.</Description>
  <Policies>
    <Authorization Class="GovernedFHIR.AI.Policy.Compartment" />
    <Audit Class="GovernedFHIR.AI.Policy.AuditLog" />
  </Policies>
  <Include Class="GovernedFHIR.AI.Tools" />
</ToolSet>
}

}
