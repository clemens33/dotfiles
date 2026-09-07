---
name: gcp-operations
description: >
  Install or operate Google Cloud safely with gcloud and bq: select explicit
  projects, authenticate with user credentials, ADC, or federation, control
  BigQuery query cost, configure FOCUS billing exports, and choose Vertex AI
  or the Gemini API. Use when setting up the Google Cloud CLI or working with
  Google Cloud resources, billing data, BigQuery, or Gemini/Vertex AI APIs.
metadata:
  category: capability
---

# Google Cloud operations

Use this skill for human-directed, auditable Google Cloud work. Keep the
target, identity, location, and expected cost visible before changing state.
Load only the relevant reference:

- [Authentication and federation](references/auth.md)
- [BigQuery safety](references/bigquery.md)
- [FOCUS export](references/focus.md)
- [Gemini API and Vertex AI](references/genai.md)

## Operating guardrails

1. Confirm the target before every operation. Set shell variables to explicit
   placeholders, then inspect identity and project:

   ```bash
   PROJECT_ID="<PROJECT_ID>"
   BILLING_PROJECT_ID="<BILLING_OR_QUOTA_PROJECT_ID>"
   gcloud auth list
   gcloud config get-value project
   gcloud projects describe "$PROJECT_ID"
   ```

2. Pass `--project="$PROJECT_ID"` whenever the command supports it; otherwise
   use the fully qualified resource name. Also pass the relevant
   `--billing-project`, `--location`, `--region`, or `--zone`; do not let an
   ambient default select a target. Fully qualify BigQuery tables as
   ``<PROJECT_ID>.<DATASET>.<TABLE>``.

3. Inspect first, then make the smallest reversible change. Show the exact
   command and impact before deletion, IAM changes, export changes, or writes.
   Do not add `--quiet` until the non-interactive behavior is understood.

4. Treat project selection, billing account selection, and credential identity
   as independent values. A quota/billing project pays for API use; it need not
   be the resource project. Never infer either from a user account or a shell
   default.

5. Keep credentials out of commands, logs, shell history, repositories, and
   issue text. Prefer short-lived user impersonation, attached identities, or
   Workload Identity Federation (WIF) over service-account keys.

## Tooling preflight

```bash
command -v gcloud bq gsutil
gcloud version
gcloud config configurations list
```

Install or upgrade the Google Cloud CLI only when missing or broken, using
Google's supported package/archive instructions. The CLI is not a Python
library; do not install it with `pip`. Add client libraries such as
`google-genai`, `google-cloud-bigquery`, `google-cloud-aiplatform`, and
`google-auth` to the application's normal lockfile and virtual environment,
not global Python.

## Configurations and authentication

Use named gcloud configurations to separate accounts and defaults. Prefer
`--configuration=<NAME>` (or `CLOUDSDK_ACTIVE_CONFIG_NAME` in a short-lived
subprocess) over changing a shared default. `gcloud auth login` authenticates
the CLI; `gcloud auth application-default login` writes credentials for client
libraries. They are separate stores and may represent different identities.

For local code, set up ADC deliberately and test token refresh without showing
the bearer token:

```bash
gcloud auth application-default print-access-token >/dev/null \
  && echo "ADC token refresh OK"
```

For production code, use an attached service account or WIF-backed external
account. Do not create long-lived keys unless an exception is documented,
approved, stored outside the repository, and rotated. See
[auth.md](references/auth.md) for the ADC search order, impersonation, and
least-privilege federation checklist.

## BigQuery and billing data

Before a query, inspect schema and partitioning, use a bounded time predicate,
avoid `SELECT *`, run a dry run, and set `--maximum_bytes_billed` on the real
job. Use a destination table only when its retention, location, overwrite mode,
and owner are explicit. A failed maximum-bytes guard must stop the job, not be
worked around. See [bigquery.md](references/bigquery.md).

FOCUS is a Google-managed immutable linked dataset, not a normal dataset to
edit. It is a normalized cost/usage export and is subject to a two-year TTL.
Querying it still incurs BigQuery compute charges. Copy to an owned,
partitioned table when retention beyond two years or derived modeling is
required; that copy incurs normal storage charges. Setup, backfill, schema
drift, location, and export-account semantics are in
[focus.md](references/focus.md).

## Gemini API versus Vertex AI

Use the current `google-genai` / `@google/genai` / `google.golang.org/genai`
client libraries; do not start new work with legacy Gemini SDKs. Choose the
Gemini Developer API for a fast prototype with an appropriately restricted API
key. Choose Gemini on Vertex AI for a Google Cloud project, IAM/ADC, regional
endpoints, and enterprise controls such as governance or data-boundary needs.
The same Gen AI SDK can target either backend, but credentials, project,
location, quotas, supported models, and controls differ. See [genai.md](references/genai.md).
