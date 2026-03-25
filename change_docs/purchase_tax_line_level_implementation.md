# Purchase Tax Implementation Approach

## Note

This file originally described the line-level tax approach. The implementation has now been simplified to use approach 1 from `purchase_tax_approaches.md`: post purchase tax as a separate tax entry in the ledger.

## Goal

Include purchase-related tax in:

- `quickbooks__general_ledger`
- `quickbooks__general_ledger_by_period`
- `quickbooks__balance_sheet`
- other ledger-derived final reports

while avoiding the old fanout problem where one purchase tax row was duplicated across every purchase line.

## Chosen Approach

Use `purchase_tax_line.amount` as the source of truth and post purchase tax as its own entry.

Expected shape:

```text
Dr Expense accounts               600
Dr GST/HST payable-style account   60
Cr AP / Cash / Credit Card        660
```

In this package, the purchase tax debit is mapped to the same tax-account framework already used for sales-side tax lines:

- match `purchase_tax_line.tax_rate_id` to `tax_rate`
- map `tax_rate.tax_agency_id` to the correct tax account
- fall back to `Sales Tax Payable` or `Global Tax Payable` style accounts when needed

This keeps the official purchase tax amount tied to QuickBooks-posted tax rather than recalculating it from line metadata.

## Why This Is Simpler

This approach does not require:

- `tax_code`
- `tax_rate_detail`
- line-level tax reconstruction
- tax reconciliation models
- synthetic fallback rows for unresolved line attribution

It only needs the posted purchase tax rows and the existing tax-account mapping inputs already used elsewhere in the package.

## Implementation Shape

### 1. Keep purchase tax enabled through `using_purchase_tax_line`

The feature still depends on:

- `using_purchase_tax_line: true`

Recommended supporting vars:

- `using_tax_rate: true`
- `using_tax_agency: true`

### 2. Post purchase tax directly from `stg_quickbooks__purchase_tax_line`

The purchase tax branch in `int_quickbooks__purchase_double_entry.sql` now:

1. starts from `stg_quickbooks__purchase_tax_line`
2. joins to the purchase header for payment account and currency conversion
3. joins to tax mapping tables for the destination tax account
4. creates one tax entry per purchase tax row

It no longer joins `purchase_tax_line` to `purchase_line`, so there is no row multiplication across expense lines.

### 3. Reuse existing tax-account mapping logic

The model now follows the same pattern already used in invoice, sales receipt, refund receipt, and journal entry tax handling:

- map agency name plus `Payable` to a liability account when possible
- otherwise fall back to configured tax payable account names

That means purchase tax now behaves more like other tax-line flows in the package.

## Reporting Impact

This change affects the ledger path only:

- `quickbooks__general_ledger`
- `quickbooks__general_ledger_by_period`
- `quickbooks__balance_sheet`
- `quickbooks__profit_and_loss`
- `quickbooks__cash_flow_statement`

It does not attempt to make `quickbooks__expenses_sales_enhanced` tax-inclusive at the purchase-line level.

## Main Tradeoff

This approach improves accounting correctness and keeps totals aligned to posted QuickBooks tax, but it does not attach tax directly to each purchase line for analytical reporting.

That tradeoff is intentional.

## Files Changed and Purpose

- `models/double_entry_transactions/int_quickbooks__purchase_double_entry.sql`
  Replaced the line-level/fallback tax branch with a direct separate-tax posting from `purchase_tax_line`.

- `dbt_project.yml`
  Removed the extra vars that were only needed for the line-level tax-code-based approach.

- `models/staging/src_quickbooks.yml`
  Removed source declarations for `tax_code` and `tax_rate_detail`, which are no longer needed.

- `models/staging/stg_quickbooks.yml`
  Removed schema entries for the unused `tax_code` and `tax_rate_detail` staged models.

- `models/docs.md`
  Removed doc blocks that were added only for the removed tax metadata staging models.

- `models/quickbooks.yml`
  Removed metadata for the intermediate line-level purchase-tax models that are no longer part of the package flow.

- `DECISIONLOG.md`
  Updated the tax-account mapping note so it no longer describes purchase tax as posting back to purchase expense accounts.

- `run_dbt.sh`
  Simplified the default vars to the ones approach 1 actually needs.

## Files Removed From the Approach 2 Attempt

- `macros/staging/get_tax_code_columns.sql`
- `macros/staging/get_tax_rate_detail_columns.sql`
- `models/staging/tmp/stg_quickbooks__tax_code_tmp.sql`
- `models/staging/tmp/stg_quickbooks__tax_rate_detail_tmp.sql`
- `models/staging/stg_quickbooks__tax_code.sql`
- `models/staging/stg_quickbooks__tax_rate_detail.sql`
- `models/intermediate/int_quickbooks__purchase_line_tax_calc.sql`
- `models/intermediate/int_quickbooks__purchase_tax_reconciliation.sql`
- `models/intermediate/int_quickbooks__purchase_tax_reconciled_lines.sql`

These were only needed for tax-code-driven line calculation and reconciliation.

## Validation Checklist

1. A purchase with one or more `purchase_tax_line` rows should produce one corresponding tax entry per posted purchase tax row.
2. The sum of purchase tax in `quickbooks__general_ledger` should equal the sum of `purchase_tax_line.amount`.
3. Purchases with multiple expense lines should no longer multiply tax.
4. Tax-related balances in the balance sheet should move in line with QuickBooks tax reports.
5. Existing non-purchase tax flows should remain unchanged.
