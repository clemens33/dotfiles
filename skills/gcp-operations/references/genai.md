# Gemini API and Vertex AI reference

## Choose the backend

| Need | Gemini Developer API | Gemini on Vertex AI |
|---|---|---|
| Fast prototype | Good fit; API key and a developer project | Works, but more Cloud setup |
| IAM and ADC | Limited caller granularity with a standard key; use restricted/auth keys | Native Google Cloud IAM, ADC, and service-account/WIF flows |
| Enterprise controls | Fewer Google Cloud resource controls | Use when regional processing, governance, audit, or other Cloud controls matter |
| Billing/quota | Key's associated project | Explicit Cloud project and location; verify model/region availability |

Both backends are accessed by the current Google Gen AI SDK. Keep backend,
project, location, model, credentials, and quota settings explicit in code and
deployment configuration. Do not assume model availability or feature parity
across regions; check current product docs before pinning a model.

## Projects are the operating boundary

Google Cloud organizes resources under organization → folders → projects;
a Cloud Billing account is linked separately to one or more projects. A project
is the practical IAM, API-enablement, audit/logging, quota, and cost-attribution
boundary—similar in purpose to a provider project or workspace, but embedded in
the wider Google Cloud resource hierarchy.

More projects improve production isolation, ownership, and finance attribution,
but repeat IAM, WIF, API, budget, log, policy, model-access, and regional setup.
Separate production from non-production. Split products further when ownership,
budget, data, or risk boundaries differ; do not create a project per runtime
instance without one of those requirements.

As of 2026-09, supported managed Gemini pay-as-you-go models use Dynamic Shared
Quota rather than a predefined per-project request quota. Splitting projects
does not manufacture capacity. Provisioned Throughput is specific to a project,
region, model, and version, so production capacity belongs in the production
boundary. Verify the current model's quota mode before using this as a design
input.

## Minimal configuration shapes

Gemini Developer API (keep the key in a secret manager or environment outside
the repository):

```python
from google import genai

client = genai.Client(api_key="<GEMINI_API_KEY>")
response = client.models.generate_content(
    model="<MODEL_ID>", contents="<PROMPT>"
)
```

Vertex AI with ADC:

```python
from google import genai

client = genai.Client(
    vertexai=True,
    project="<PROJECT_ID>",
    location="<LOCATION>",
)
response = client.models.generate_content(
    model="<MODEL_ID>", contents="<PROMPT>"
)
```

Enable the required API, billing, and IAM role before the first Vertex call.
Prefer `roles/aiplatform.user` or a narrower custom/resource role over Owner or
Editor. For the Developer API, restrict keys to the intended API and, where
supported, application origins/IPs; rotate or revoke exposed keys. API keys
are not a substitute for IAM or WIF.

Use the SDK's current package names (`google-genai`, `@google/genai`,
`google.golang.org/genai`). Test authentication and authorization separately
from model behavior, and pin a supported SDK/model version with a migration
plan.

References: [Google Gen AI SDK](https://cloud.google.com/vertex-ai/generative-ai/docs/sdks/overview),
[Vertex AI quickstart](https://cloud.google.com/vertex-ai/generative-ai/docs/start/quickstart),
[Gemini API keys](https://ai.google.dev/gemini-api/docs/api-key), and
[backend migration](https://ai.google.dev/gemini-api/docs/migrate-to-cloud).
For capacity planning, see [Vertex AI throughput quota](https://cloud.google.com/vertex-ai/generative-ai/docs/resources/throughput-quota)
and [Provisioned Throughput](https://cloud.google.com/vertex-ai/generative-ai/docs/provisioned-throughput/measure-provisioned-throughput).
