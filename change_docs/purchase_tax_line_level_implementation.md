# Purchase Tax Line-Level Implementation Approach

## Goal

Implement the preferred purchase-tax solution using line-level tax logic so that:

- purchase-related tax is included in `quickbooks__general_ledger`
- downstream final reports reflect purchase tax
- tax is attached to the correct purchase lines
- current fanout behavior is removed

This document assumes the preferred direction is:

- create tax records per purchase line
- use line tax metadata such as `account_expense_tax_code_id`
- reconcile back to the posted purchase tax totals

## Core Principle

The line-level approach should not blindly spread tax across all lines in a purchase.

Instead:

1. determine the tax treatment of each line
2. calculate or derive the tax amount for that line
3. create one tax record per qualifying line
4. reconcile the total back to the posted `purchase_tax_line.amount`

## Current Package Gaps

The current package already has some useful fields, but it is missing key pieces for a full line-level tax implementation.

### Available now

- `purchase_tax_line.amount`
- `purchase_tax_line.tax_rate_id`
- `purchase_line.account_expense_tax_code_id`
- `purchase_line.item_expense_tax_code_id`
- `tax_rate`
- `tax_agency`

### Not currently staged in this package

- `tax_code`
- `tax_rate_detail`

### Available in schema macro but not carried through the staged purchase line model

- `account_expense_tax_amount`

This means the package has some of the ingredients, but not enough yet to reliably reproduce QuickBooks tax behavior from metadata alone.

## Recommended Implementation Shape

## Phase 1: Expose Missing Line-Level Tax Inputs

First, extend staging so the purchase line model carries more tax information.

Recommended changes:

1. Update `stg_quickbooks__purchase_line.sql` to expose:
   - `account_expense_tax_amount`
   - `item_expense_tax_code_id` if needed downstream
2. Update schema docs for the new staged columns.
3. Confirm whether the raw connector actually populates `account_expense_tax_amount` in your environment.

Why this matters:

- if `account_expense_tax_amount` is populated, it is a stronger line-level signal than recalculating everything from tax code
- it can reduce the amount of tax logic we need to rebuild manually

## Phase 2: Add Missing Tax Configuration Models

If the line-level approach is going to rely on tax code logic, add staging for the missing tax configuration tables.

Recommended new staged sources and models:

- `tax_code`
- `tax_rate_detail`

These are likely needed because:

- a tax code can represent more than one rate
- tax behavior may depend on grouped tax configuration
- the relationship between line tax code and actual rate posting may not be recoverable from `tax_rate` alone

Without these tables, `account_expense_tax_code_id` may not be enough to calculate the true tax for the line.

## Phase 3: Create a New Intermediate Tax Calculation Model

Add a dedicated intermediate model, for example:

- `int_quickbooks__purchase_line_tax_calc`

Its grain should be:

- one row per purchase line tax result

Suggested responsibilities:

1. start from `stg_quickbooks__purchase_line`
2. identify the tax code for each line
3. derive the tax behavior for that code
4. calculate `calculated_tax_amount` per line
5. keep the destination expense account and class from the same purchase line
6. preserve `purchase_id`, `index`, `source_relation`, `account_id`, and `class_id`

Suggested output columns:

- `purchase_id`
- `source_relation`
- `purchase_line_index`
- `tax_code_id`
- `tax_rate_id` if derivable
- `expense_account_id`
- `class_id`
- `line_amount`
- `calculated_tax_amount`
- `tax_calc_method`
- `is_taxable`

## Phase 4: Reconciliation Against Posted Purchase Tax

This is the most important control in the design.

Even if tax is calculated per line, the package should still reconcile the sum of line tax back to the posted purchase tax amount from `stg_quickbooks__purchase_tax_line`.

Recommended reconciliation process:

1. aggregate `calculated_tax_amount` by `purchase_id`
2. aggregate posted `purchase_tax_line.amount` by `purchase_id`
3. compare both totals
4. if the difference is only rounding, push the remainder to one designated line
5. if the difference is material, flag the purchase for audit or fallback logic

Suggested output model:

- `int_quickbooks__purchase_tax_reconciliation`

Suggested fields:

- `purchase_id`
- `source_relation`
- `calculated_tax_total`
- `posted_tax_total`
- `tax_difference`
- `reconciliation_status`

## Phase 5: Replace the Current Purchase Tax Fanout Logic

Once the line-level tax model is ready, replace the current `purchase_tax_lines` union branch in:

- `models/double_entry_transactions/int_quickbooks__purchase_double_entry.sql`

Current problem:

- purchase tax joins to all purchase lines by `purchase_id`
- this causes multiplication of tax rows

Target behavior:

- use the new line-level tax calculation model instead of joining `purchase_tax_line` directly to all purchase lines
- generate one tax row per purchase line
- use the expense account and class from the specific purchase line
- keep the credit side tied to the purchase payment account

Result:

- one debit tax-adjusted expense posting per line
- one corresponding credit posting per line
- no fanout
- tax totals remain controlled

## Phase 6: Decide How Final Reporting Should Behave

There are two possible reporting outcomes for the line-level approach.

### Option A

Only update the general ledger path.

Impact:

- `quickbooks__general_ledger`
- `quickbooks__general_ledger_by_period`
- `quickbooks__balance_sheet`
- `quickbooks__profit_and_loss`

This is the smaller change if your main goal is official accounting output.

### Option B

Also update purchase transaction reporting models to reflect line-level tax-inclusive amounts.

Possible touch points:

- `int_quickbooks__purchase_transactions`
- `int_quickbooks__expenses_union`
- `quickbooks__expenses_sales_enhanced`

This is useful if business users want the expense detail model to show tax-inclusive line values as well.

## Recommended Fallback Logic

Because line-level tax reconstruction may not always be possible, define a clear fallback order.

Suggested order:

1. use `account_expense_tax_amount` if raw data provides it
2. else calculate from tax-code configuration
3. reconcile to `purchase_tax_line.amount`
4. if not reconcilable, flag the record and avoid silent distortion

This avoids forcing the package to invent tax where the metadata is incomplete.

## Recommended Validation Rules

Add tests or validation queries for the following:

1. no purchase has tax fanout greater than expected
2. one calculated tax result exists per qualifying purchase line
3. summed line tax matches posted purchase tax by purchase
4. general ledger remains balanced
5. period totals in `quickbooks__general_ledger_by_period` are stable before and after the change except for intended purchase-tax effects
6. sample GST/HST accounts in balance sheet and tax reports reconcile to expected values

## Files Changed and Purpose

- `dbt_project.yml`
  Adds new variables and feature flags for `tax_code` and `tax_rate_detail` so the new tax-calculation path can be enabled safely and remain backward compatible.

- `models/docs.md`
  Adds documentation text for `tax_rate_detail` so the new staging models have package docs.

- `models/double_entry_transactions/int_quickbooks__purchase_double_entry.sql`
  Replaces the old purchase-tax fanout logic with the new reconciled line-level purchase-tax rows.

- `models/quickbooks.yml`
  Adds model metadata entries for the new intermediate purchase-tax models.

- `models/staging/src_quickbooks.yml`
  Declares the new raw sources `tax_code` and `tax_rate_detail`, and documents the newly exposed purchase-line tax fields.

- `models/staging/stg_quickbooks.yml`
  Adds schema documentation for the new staged tax models and the extra purchase-line tax columns.

- `models/staging/stg_quickbooks__purchase_line.sql`
  Exposes `account_expense_tax_amount` and `item_expense_tax_code_id` so line-level tax logic has the required fields.

- `macros/staging/get_tax_code_columns.sql`
  Defines the expected column structure for raw `tax_code` data.

- `macros/staging/get_tax_rate_detail_columns.sql`
  Defines the expected column structure for raw `tax_rate_detail` data.

- `models/intermediate/int_quickbooks__purchase_line_tax_calc.sql`
  Calculates provisional tax per purchase line using explicit line tax amount first, then tax metadata where needed.

- `models/intermediate/int_quickbooks__purchase_tax_reconciliation.sql`
  Compares summed line-level calculated tax against posted `purchase_tax_line` totals and determines reconciliation status.

- `models/intermediate/int_quickbooks__purchase_tax_reconciled_lines.sql`
  Produces the final purchase-tax rows used by the purchase double-entry model, including rounding adjustments and fallback rows.

- `models/staging/stg_quickbooks__tax_code.sql`
  Stages raw `tax_code` data into a usable dbt model.

- `models/staging/stg_quickbooks__tax_rate_detail.sql`
  Stages raw `tax_rate_detail` data into a usable dbt model.

- `models/staging/tmp/stg_quickbooks__tax_code_tmp.sql`
  Pulls raw `tax_code` source data into the package staging flow using the standard temporary union pattern.

- `models/staging/tmp/stg_quickbooks__tax_rate_detail_tmp.sql`
  Pulls raw `tax_rate_detail` source data into the package staging flow using the standard temporary union pattern.

## Risks and Drawbacks

This approach is stronger than proportional allocation, but it still has risks.

- depends on tax metadata that is not fully staged today
- may require adding new source tables not currently modeled by the package
- tax code interpretation can be complex
- historical effective rate behavior may not always be reconstructable from current configuration
- manual overrides and rounding may still create differences from posted tax totals
- implementation complexity is meaningfully higher than a simple join fix

## Recommendation

If the team wants the second approach, the safest way to implement it is:

1. expose more line tax fields first
2. add the missing tax configuration models
3. build a dedicated line-level tax calculation model
4. reconcile every purchase back to posted purchase tax totals
5. only then replace the purchase tax branch in the double-entry model

This keeps the design aligned with the senior direction while reducing the risk of introducing a different kind of tax distortion.
