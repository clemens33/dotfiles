# FOCUS Cloud Billing export reference

FOCUS (FinOps Open Cost and Usage Specification) is a normalized schema for
technology cost and usage data. As of 2026-09, Google Cloud's FOCUS usage-cost
export is a Preview feature. Re-check the linked official docs before relying
on Preview behavior. It creates a Google-provided immutable linked BigQuery
dataset and table for one Cloud Billing account; do not treat either as an
application-owned dataset.

## Setup checklist

1. Choose or create a billing-administration project and enable billing on it.
   Link it to the same Cloud Billing account whose data is being exported.
2. Confirm the operator has the required billing-account export permission and
   project permissions (currently Billing Account Costs Manager or Billing
   Account Administrator, plus Project IAM Admin and BigQuery Admin on the
   dataset project). Use temporary elevation where policy allows; keep ongoing
   analyst/query access narrower than setup administration access.
3. Enable the BigQuery API in the selected project.
4. In Cloud Billing → Billing export → BigQuery export, enable FOCUS, select
   the project, choose the dataset location, and save. Google's supported setup
   is Console-driven; no documented `gcloud` or public REST enablement method
   exists. Do not automate a private Console endpoint. Prefer a supported `EU`
   or `US` multi-region when policy allows. Dataset location is immutable and
   supported single-region choices are limited.
5. Wait for the export to create its immutable dataset/table and verify that
   the Google-managed export service account
   `billing-export-bigquery@system.gserviceaccount.com` remains an owner.
   Removing it stops updates and can cause data loss.

Use placeholders in scripts; never copy a real billing account ID into a
public example. The generated names contain the billing account ID and
location, so discover them from metadata rather than guessing.

## Data availability and semantics

- Initial data can take hours to appear. A multi-region location can backfill
  from the start of the previous month; the first backfill can take up to five
  days. A supported single region starts at enablement and is not retroactive.
- Disabling creates a gap; re-enabling with the same project/location can reuse
  the immutable dataset but does not backfill the gap. A changed project or
  location creates a new dataset with no automatic historical backfill.
- Export schemas can gain fields. Put a stable view in front of the export and
  update that view when the upstream schema changes. Do not manually merge or
  insert rows into the managed table.
- `BilledCost` is the invoicing-oriented cost after discounts and credits,
  excluding amortization of purchases; use it for cash-basis allocation and
  reconciliation. Keep billing currency and billing-period boundaries in
  grouping logic. Use export-time metadata to distinguish late updates from
  the original usage period.
- A single billing account export includes usage/cost for all projects paid by
  that account. Enforce access at the dataset, view, or row level before
  sharing reports.

## Why BigQuery, not a billing API or Steampipe

Cloud Billing APIs manage accounts, project links, budgets, and catalog/pricing
metadata; they do not expose the complete historical charged line-item ledger.
Steampipe and its Google Cloud plugin are useful for low-volume, live
control-plane inventory. Neither replaces the account-wide FOCUS fact export.
Use BigQuery FOCUS plus an owned warehouse landing for durable billing history,
late corrections, reconciliation, and dashboards. This is BigQuery, not
Bigtable.

## Cost and TTL

The Google-provided linked dataset does not charge storage for its FOCUS data,
but every query can incur BigQuery compute charges. Run dry runs and set a
maximum bytes billed cap. The managed FOCUS table has a two-year TTL; rows older
than two years are automatically deleted. For longer retention, schedule an
incremental copy into an owned, partitioned table with an explicit retention
policy. The owned copy incurs normal storage and query costs; give the copy a
shorter TTL when history is not required. Do not attempt to set a custom TTL on
the immutable source.

References: [FOCUS setup](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-focus-setup),
[FOCUS schema](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/focus-export),
and [Cloud Billing BigQuery export limitations](https://cloud.google.com/billing/docs/how-to/export-data-bigquery-setup).
