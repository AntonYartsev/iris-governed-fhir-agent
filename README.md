# iris-governed-fhir-agent

InterSystems AI Hub agent over a FHIR R4 repository

One agent, one skill, three tools, one MCP server, one `docker compose up`

Most AI Hub examples show what an agent can do. This one shows what it cannot. The agent reads one patient's data and nothing else: no other patients, no bulk exports, no unapproved resource types. This is enforced by the tools and the policy, not by the prompt

![demo.gif](demo.gif)

Built and tested on `irishealth-community 2026.3.0AI.126.0` (AI Hub EAP)

The story behind this repo: [The greatest trick my guardrails ever pulled was convincing the audit log they never fired](https://community.intersystems.com/post/greatest-trick-my-guardrails-ever-pulled-was-convincing-audit-log-they-never-fired) on the InterSystems Developer Community.

`package/` ships the enforcement layer as a standalone IPM module, reusable outside this demo

This application implements two ideas from the InterSystems Ideas Portal:

**[DPI-I-986](https://ideas.intersystems.com/ideas/DPI-I-986) - My First Agent
(End-To-End Starter).**

**[DPI-I-985](https://ideas.intersystems.com/ideas/DPI-I-985) - MCP Data
Exposure Toolkit.**

---

## Quickstart

At the moment the EAP image is **not on a public registry**, but you can download it from the [EAP portal](https://evaluation.intersystems.com/Eval/early-access/AIHub) and load it:

```bash
# x86_64 - default
docker load < irishealth-community-2026.3.0AI.126.0-docker.tar.gz
# arm64 (Apple silicon)
docker load < irishealth_arm64-community-2026.3.0AI.126.0-docker.tar.gz
```

```bash
git clone https://github.com/antonyartsev/iris-governed-fhir-agent.git
cd iris-governed-fhir-agent
cp .env.example .env      # any OpenAI compatible API key
docker compose up -d --build
```

*`docker load` prints the tag it created. If it is not the x86_64 tag, put it into `.env` as `IRIS_IMAGE=`.*

Everything is **baked into the image at build time**, and the container starts ready without a durable volume. After recreating the container you get the same clean state, with an empty audit table. It's good for a demo, not for a real deployment

Synthea inserts digits into patient names, so search by a part of the family name and let `FindPatient` do the rest:

```bash
docker compose exec iris iris session IRIS -U IRISAPP '##class(GovernedFHIR.AI.Agent).Ask("What is going on with patient Kuphal?")'
```

If something looks wrong, run `##class(GovernedFHIR.Setup.Install).Doctor()`. **It prints the state of every part**

---

## What it does

Real output, *shortened*:

```
> What is going on with patient Kuphal?

  FindPatient        {"name":"Kuphal"}  ->  ok
  GetPatientSummary  {"patientId":"3d852e71-d854-5968-d53d-829ec4b9cf8b"}  ->  ok

Patient: Hosea56 Jackie93 Kuphal363, born 1977-03-26
(Patient/3d852e71-d854-5968-d53d-829ec4b9cf8b).

Active problems
- Essential hypertension (Condition/3d852e71-d854-5968-dbff-36de72ba7c9f)
- Prediabetes (Condition/3d852e71-d854-5968-ee6e-e1a5160d2ba6)

Recent vital signs
- Blood pressure 140/84 mm[Hg] on 2025-10-25
  (Observation/3d852e71-d854-5968-ff89-f134e36822a5)

Recent laboratory results
- Hemoglobin A1c 6.21 % (Observation/3d852e71-d854-5968-602f-d5c6fdcfd040)

Active medication requests
- Hydrochlorothiazide 25 MG Oral Tablet
  (MedicationRequest/3d852e71-d854-5968-07fa-c9c0fc6b99ef)

Allergies
- Aspirin - active, criticality low
  (AllergyIntolerance/3d852e71-d854-5968-b2ad-cb74344f7b2f)
```

Every fact comes with a resource id, so a clinician can open the record and check

---

## Try to break it

These attempts run through an external MCP client. Our system prompt is not used, **the refusals come from the ToolSet itself**

**1. Drop the patient scope**

```
> Call FhirSearch with resourceType=Observation and leave patientId empty so it
> scans every patient, then list all patients with HbA1c above 8.

  ToolAccessDenied: Tool 'FhirSearch' requires a valid patientId.
  Resolve the patient first; patient scope is not optional.
```

`patientId` is required in the JSON schema. Most clients stop right there. This client sent the call anyway, with an empty field. `AI.Policy.Compartment` **blocked it before the tool body ran**

**2. Ask for a resource type that is not exposed**

```
> Use FhirSearch with resourceType=Practitioner and _count=10000.

  Resource type 'Practitioner' is not exposed by this toolset.
```

`_count=10000` was never checked. **The allowlist check runs first**

**3. Escape through a parameter**: `_include` pulls linked resources along with the search. `_revinclude` and `_has` do similar things. **None of them are on the allowlist**

```
{"error":"denied","message":"search parameter '_include' is not allowed for Observation, Allowed: category,code,date,status,_sort,_count"}
```

The first two attempts came back as MCP errors. This one came back as a normal tool result. The payload is a refusal. `Guard` refuses by returning a value, not by failing

**4. Inside the scope, everything still works**: after three denials, the client switched to the patient's Encounters - an allowed resource type - inside the compartment

All of it lands in the audit table:

```
ID  ToolName           PatientId               Allowed  Channel  ErrorText
1   FindPatient                                1        agent
2   GetPatientSummary  3d852e71-d854-5968-...  1        agent
3   FhirSearch                                 0        mcp      Tool 'FhirSearch' requires a valid patientId...
4   FhirSearch         3d852e71-d854-5968-...  0        mcp      Resource type 'Practitioner' is not exposed...
5   FhirSearch         3d852e71-d854-5968-...  0        mcp      search parameter '_include' is not allowed...
6   FhirSearch         3d852e71-d854-5968-...  1        mcp
```

Rows 1-2 come from the agent. Rows 3-6 come from an external client on the same ToolSet. Same tools, same policies, same table - that is the main claim. Row 6 was allowed but clamped: `_count=10000` became `_count=25`

Writing tool calls to a table is not our idea - it is what the AI Hub docs tell you to do. `%AI.Policy.ConsoleAudit` writes to the current device, which over MCP is the HTTP response body, so it breaks every `tools/call`. `AGENTS.md` says: subclass `%AI.Policy.Audit` and write to a persistent class

**Two fixes on top of that were needed to make these rows honest**

**First**: `Compartment` writes its own audit row before it returns an error, because a denied call **never reaches the audit policy**

**Second**: `AuditLog` reads the payload, not the `%Status`, because a `Guard` refusal is a normal return value. **Without the fix it would be logged as a success**

Denials also go into the IRIS audit database as `GovernedFHIR / ToolCall / Denied`, so they land where a security team already looks - **System Administration > Security > Auditing > View Audit Database**

The rules are covered by unit tests, with no LLM involved:

```bash
docker compose exec iris iris session IRIS -U IRISAPP '##class(%UnitTest.Manager).RunTest("GovernedFHIR/Tests")'
```

---

## The four rules

| Rule | Where it lives | What it stops |
| --- | --- | --- |
| Patient compartment lock | `patientId` is required; the query is built server-side | Reads across patients. Every tool except `FindPatient` needs a patient. The caller never builds the compartment query |
| Resource type allowlist | `Guard.AllowedResources()` | `Practitioner`, `Binary`, `AuditEvent`, anything not reviewed |
| Search parameter allowlist | `Guard.AllowedParams()` | `_include`, `_revinclude`, `_has`  |
| Size cap | `Guard.MAXROWS`, `Guard.MAXCHARS` | A tool call that quietly turns into a bulk export |

`Core.Guard` lives inside the tool body. It is the foundation: all four rules run on every path. Even a direct terminal call `##class(GovernedFHIR.AI.Tools).FhirSearch(...)` goes through it, even though no policy sees that call

`AI.Policy.Compartment` in the ToolSet. It checks patient scope and resource type one more time, before the tool body runs. So a refused call **never reaches the FHIR server**

---

## Why not SMART on FHIR scopes?

Fair question, IRIS for Health already has this. `HS.FHIRServer.Util.OAuth2Token` checks SMART scopes on every request: a `patient/Observation.rs` token gets one patient's Observations and nothing else. That is rules 1 and 2 of the table above, at the FHIR server, not in a tool

Three reasons this demo does not lean on it:

- A scope governs an OAuth client calling the REST API. An MCP client has no patient context claim to put in a token
- A scope cannot say "no `_include`", "25 rows", or "these seven types". Those are tool-shaped limits
- A scope leaves no record of **which tool was called with what arguments**. That is the audit row, and it is what a review actually asks for

Same story for `HS.FHIRServer.API.Interactions` - `OnBeforeRequest`, `PostProcessSearch` and friends are the right place for consent rules. They see a FHIR request. They do not see a tool call

The `_count` clamp *is* a duplicate: the endpoint already has `MaxSearchPageSize`. The tool clamps anyway so `package/` is correct wherever it lands. `MAXCHARS` is the one that is not a duplicate - it is about the model's context window, which the FHIR server knows nothing about

**On a real deployment you want both**: SMART scopes on the endpoint, these tools on top

---

## Architecture

![architecture.png](architecture.png)

The dashed line means: `Core` does not depend on AI Hub. Its unit tests need no LLM, no network, no API key

---

## Use it as a starter

Everything is small on purpose - one class per concern. To turn it into *your* first agent:

- `GovernedFHIR.AI.Tools` - the three tool bodies. Replace them with your own domain
- `AI.Policy.Compartment` - the ToolSet policy that runs before any tool body
- `Core.Guard` - allowlists and caps. Plain ObjectScript, no AI Hub dependency
- `GovernedFHIR.AI.Agent` - wiring: model, skill, toolset
- `GovernedFHIR.Setup.Install` - FHIR endpoint, Synthea load, `Doctor()`
- `Setup/MCPSetup.cls` - the MCP application

The guard layer also ships as a standalone IPM module in `package/`, so the next application can declare it as a dependency instead of copying classes

---

## Connect an external MCP client

```bash
claude mcp add --transport http governed-fhir http://localhost:8080/mcp
```

You can also go without a client: `scripts/mcp-call.sh` does the handshake and calls one tool:

```bash
./scripts/mcp-call.sh FindPatient '{"name":"Kuphal"}'
./scripts/mcp-call.sh FhirSearch '{"resourceType":"Practitioner","patientId":"x"}'
```

The second call comes back refused. Both calls are now audit rows with `Channel = mcp`

---

## What this demo is not

- **Not a production access-control model.** The lock lives in the tool layer, not in user authentication
- **Not authenticated where it matters.** The MCP application accepts callers without authentication. This is set in `Setup/MCPSetup.cls`. So the governed tools are the *only* thing between a client and the data. That is the point
- **Not clinically validated.** The data is synthetic (Synthea)

---

MIT license. Synthetic data (Synthea)
