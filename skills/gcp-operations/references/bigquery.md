# BigQuery safety reference

## Cost-bounded query loop

Use one project for the data and explicitly choose the project that owns the
query job and quota. Inspect before reading large tables:

```bash
DATA_PROJECT_ID="<DATA_PROJECT_ID>"
QUERY_PROJECT_ID="<QUERY_OR_BILLING_PROJECT_ID>"
TABLE_REF="${DATA_PROJECT_ID}:<DATASET>.<TABLE>"

bq show --project_id="$DATA_PROJECT_ID" "$TABLE_REF"
bq query --project_id="$QUERY_PROJECT_ID" \
  --use_legacy_sql=false \
  --dry_run \
  --maximum_bytes_billed=1000000000 \
  --parameter='start_ts:TIMESTAMP:<UTC_START>' \
  'SELECT ServiceName, SUM(BilledCost) AS cost
     FROM `<DATA_PROJECT_ID>.<DATASET>.<TABLE>`
    WHERE BillingPeriodStart >= @start_ts
    GROUP BY ServiceName'
```

Review the dry-run estimate and schema before running. Keep the same
`--maximum_bytes_billed` on the real job; it fails without charge if the query
would exceed the cap. Filter partition columns, project only needed columns,
avoid wildcard tables and accidental cross joins, and use views to normalize
vendor-managed export schemas. Parameterize runtime values; BigQuery cannot
parameterize table identifiers, so construct those only from separately
validated project/dataset/table components. Prefer cached results for repeated
read-only queries, but treat cache as best-effort: non-deterministic queries,
changed inputs, wildcard queries, and destination tables can bypass it.

## Writes and retention

For a result that must persist, choose a destination table explicitly and state
whether the job may overwrite it. Use a scratch dataset for experiments; set a
short table or partition expiration there. Keep dataset/table location aligned
with every source table. Treat DDL, DML, `CREATE OR REPLACE`, `WRITE_TRUNCATE`,
and table deletion as mutations requiring explicit review. Never write into a
Google-managed billing export table; copy into an owned dataset first.

Cost controls are not authorization. IAM still needs the minimum
`bigquery.jobs.create` and dataset/table read or write permissions. Do not put
raw billing rows or access tokens in logs or exported artifacts.

References: [estimate and control costs](https://cloud.google.com/bigquery/docs/best-practices-costs),
[bq query flags](https://cloud.google.com/bigquery/docs/reference/bq-cli-reference), and
[cached results](https://cloud.google.com/bigquery/docs/cached-results).
