# Google Cloud authentication reference

## Separate CLI auth from ADC

These commands affect different credential stores:

```bash
gcloud auth login --account="<USER_EMAIL>"
gcloud auth list
gcloud auth application-default login "<USER_EMAIL>"
gcloud auth application-default set-quota-project "<QUOTA_PROJECT_ID>"
gcloud auth application-default print-access-token >/dev/null \
  && echo "ADC token refresh OK"
```

Create a named configuration once, then address it explicitly so a command
cannot silently use another account or project:

```bash
gcloud config configurations list
gcloud config configurations create "<CONFIG_NAME>"
gcloud --configuration="<CONFIG_NAME>" config set account "<USER_EMAIL>"
gcloud --configuration="<CONFIG_NAME>" config set project "<PROJECT_ID>"
gcloud --configuration="<CONFIG_NAME>" config set billing/quota_project "<QUOTA_PROJECT_ID>"
gcloud --configuration="<CONFIG_NAME>" config list
```

Avoid `gcloud config configurations activate` in a shared shell unless the
change is intentional; it changes the active default for later commands.

`gcloud` uses its own active account. Google client libraries use ADC; CLI
login does not configure ADC. The quota project must grant the caller
`serviceusage.services.use` when a client library needs billable/quota-backed
APIs. Use a separate `--billing-project` for a one-off CLI command when that
is the desired payer. `print-access-token` emits a bearer token: suppress its
output for health checks, and never paste, persist, or log it.

## ADC search order

Client libraries check, in order:

1. `GOOGLE_APPLICATION_CREDENTIALS` (service-account key or external-account
   configuration, including WIF/workforce federation).
2. The well-known file written by `gcloud auth application-default login`.
3. The attached service account exposed by the metadata server.

Before running code, print the path and inspect any external-account
configuration you were handed. A credential configuration is executable input:
do not accept one from an untrusted repository or URL. Unset
`GOOGLE_APPLICATION_CREDENTIALS` after a scoped test so it cannot silently
override intended ADC. In production on Google Cloud, an attached service
account is preferred; grant it only the roles and resource access required.

## Impersonation and WIF

For local permission tests, use short-lived impersonation instead of a key:

```bash
gcloud auth application-default login \
  --impersonate-service-account="<SERVICE_ACCOUNT_EMAIL>"
gcloud --impersonate-service-account="<SERVICE_ACCOUNT_EMAIL>" \
  projects describe "<PROJECT_ID>"
```

The caller needs `iam.serviceAccounts.getAccessToken`, normally via
`roles/iam.serviceAccountTokenCreator` on the target service account. Grant it
only to the tester or workload that needs impersonation.

For CI or another cloud, use WIF with an external OIDC/SAML identity. Bind a
dedicated service account per workload, restrict the provider's attribute
mapping and conditions to immutable, unique claims, and grant
`roles/iam.workloadIdentityUser` only to the exact principal(s) that need
impersonation. Grant the service account resource-level roles, not broad
project Owner/Editor roles. Keep the pool/provider and service account in a
controlled administrative boundary, enable relevant IAM and STS data-access
audit logs, and review bindings after changes. WIF removes the need for static
service-account keys; it does not make an over-privileged service account safe.

References: [ADC search order](https://cloud.google.com/docs/authentication/application-default-credentials),
[gcloud auth](https://cloud.google.com/sdk/gcloud/reference/auth), and
[WIF best practices](https://cloud.google.com/iam/docs/best-practices-for-using-workload-identity-federation).
Use the official [Google Cloud CLI installation guide](https://cloud.google.com/sdk/docs/install)
for new machines.
