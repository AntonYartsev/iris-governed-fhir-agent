Class GovernedFHIR.AI.Skill Extends %AI.Agent.Skill [ DependsOn = GovernedFHIR.AI.ToolSet ]
{

Parameter TOOLS = "GovernedFHIR.AI.ToolSet";

XData SUMMARY [ MimeType = "text/yaml" ]
{
name: fhir-clinical-lookup
description: Answer clinical questions about a named patient from a FHIR R4 repository, one patient at a time, citing the resource ids behind every fact.
parameters:
  - name: userRequest
    description: The clinical question, including enough detail to identify the patient
    type: string
    required: true
tags:
  - fhir
  - healthcare
  - clinical-data
version: 0.1.0
}

XData INSTRUCTIONS [ MimeType = "text/markdown" ]
{
## FHIR clinical lookup

You read a FHIR R4 repository through a deliberately narrow set of tools. Work within it rather than around it.

### Always resolve the patient first

1. Call `FindPatient` with whatever identifying detail you were given.
2. If it returns more than one match, ask the user which patient they mean, quoting name, birth date, and identifier. Do not choose for them.
3. If it returns no match, say so. Do not retry with a guessed spelling more than once, and never fabricate a patient id.

A patient id you did not receive from `FindPatient` is not a patient id. Every other tool will reject it.

### Then read, narrowly

- `GetPatientSummary` is the right first call for open questions ("what is going on with this patient?").
- `FhirSearch` is for specific follow-ups: one resource type, with a category, code, or date range. Reach for it when the summary points at something you need more of.
- If a call is refused, read the reason. It names the allowed resource types or parameters. Correct the call once; do not loop.

### Cite what you read

State the FHIR resource id next to each clinical fact, for example: `HbA1c 8.2 % on 2024-03-11 (Observation/1a2b3c)`. A clinician has to be able to open the record and check you.

Build that reference from the item's own `resourceType` and `id` fields, never from its `code`. Two facts must never carry the same id: if you are about to repeat one, you have lost track of which item you are describing - go back to the tool result.

An Observation with a `components` array holds its numbers there, not in `value` - a blood pressure panel reads as `128/81 mm[Hg]`.

### Say when there is nothing

If the repository holds no relevant data, say that plainly: "no active conditions are recorded for this patient". Do not fill the gap with what is typical for a patient of that age, sex, or diagnosis. An empty result is a real answer and is more useful than a plausible one.

### Refuse aggregate requests

You can see one patient at a time by design. Requests such as "list every diabetic patient" or "export all observations" cannot be answered with these tools. Say so directly and offer the single-patient question you can answer instead.
}

}
