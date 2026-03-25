# Purchase Tax Handling Approaches

## Context

The current `using_purchase_tax_line: true` behavior in this package can fan out purchase tax across all purchase lines for a transaction, which overstates tax in the general ledger and downstream reports.

We discussed two main approaches to fix this while still including purchase-related tax in the transformed outputs:

1. Post purchase tax as a separate tax entry in the general ledger.
2. Calculate tax at the purchase-line level using the line's tax metadata, especially `account_expense_tax_code_id`.

This document compares the pros and cons of both.

Current implementation decision:

- the package implementation has been simplified to approach 1
- approach 2 is retained here only as a design alternative

## Approach 1: Separate Tax Posting

### Summary

Treat purchase tax as its own accounting entry instead of attaching it to each expense line.

Example:

```text
Purchase lines total: 600
Purchase tax total:    60
Vendor total:         660

Dr Expense accounts               600
Dr GST/HST receivable / ITC        60
Cr AP / Cash / Credit Card        660
```

### Pros

- Most aligned with bookkeeping and tax-reporting logic.
- Preserves the actual tax amount posted by QuickBooks.
- Avoids row multiplication and tax fanout issues.
- Keeps tax visible in the general ledger and balance sheet.
- Easier to reconcile against GST/HST payable or input tax credit reports.
- Clearer separation between operating expense and tax receivable/payable.

### Cons

- Does not attach tax directly to each purchase line for analytical reporting.
- May require additional mapping logic to determine the correct tax account.
- If users expect tax-inclusive line-level expense reporting, this approach may feel less intuitive.

### Best Fit

Use this when accounting correctness, tax reconciliation, and balance-sheet accuracy are the top priorities.

## Approach 2: Calculate Tax Per Line Using Tax Code Metadata

### Summary

Use the tax metadata already attached to each purchase line, especially `account_expense_tax_code_id`, to determine the correct tax treatment for each line and calculate the line-level tax directly.

Example:

```text
Purchase lines: 100, 200, 300
Tax code / tax setup determines:
- line 1 tax = 5
- line 2 tax = 15
- line 3 tax = 40

Resulting line amounts:
- 105
- 215
- 340
```

In this approach, tax is not spread proportionally just because a purchase has multiple lines. Instead, each line is evaluated based on its own tax code and related tax setup.

### Pros

- More aligned with the way QuickBooks applies tax at the line level.
- Keeps tax connected to the line that actually triggered it.
- Avoids the current fanout problem.
- Better than proportional allocation when only some lines are taxable.
- Better than proportional allocation when different lines use different tax codes.
- Produces line-level tax detail that is useful for reporting by vendor, account, department, or item.
- Can support more accurate expense-line enrichment if the required tax metadata is available.

### Cons

- This package does not currently stage a `tax_code` model or a `tax_rate_detail` model, so the required tax metadata may not be fully available yet.
- A tax code often represents a grouping of one or more tax rates, so `account_expense_tax_code_id` alone may not always be enough.
- Historical tax behavior can depend on the effective rate at the time of the transaction, not just the current tax setup.
- Manual overrides, rounding adjustments, inclusive tax handling, or exemptions can still cause calculated tax to differ from what QuickBooks actually posted.
- If the calculation logic differs from QuickBooks' own logic, reconciliation against tax reports can become difficult.
- Even if line-level calculation is correct analytically, it is still safer to reconcile against actual posted tax totals from `purchase_tax_line`.

### Best Fit

Use this when line-level tax attribution is important and the source data contains enough tax metadata to reproduce QuickBooks tax logic reliably.

## Important Design Principle

If possible, use `purchase_tax_line.amount` as the source of truth for the total tax posted on the purchase.

Tax code fields such as `account_expense_tax_code_id` are useful for line-level tax determination, classification, and validation, but they should not automatically be treated as the sole source of truth unless you are confident the full tax configuration is available and stable.

## Suggested Use of Tax Metadata

Tax-related metadata can still help:

- `purchase_tax_line.amount`: best source for the actual tax total posted on the document.
- `account_expense_tax_amount`: potentially the best line-level amount if populated in raw data.
- `account_expense_tax_code_id`: useful for identifying the intended tax treatment of a line.
- `tax_rate` and `tax_agency`: useful for tax mapping and reporting context.
- `tax_code` and `tax_rate_detail`: likely required if you want to fully reproduce QuickBooks tax logic from metadata.

Recalculating tax from tax code metadata can be a valid modeling approach, but it is strongest when used together with posted tax data for reconciliation.

## Recommendation

If the goal is to make the general ledger, balance sheet, and tax-related final reports more accurate, the safer default is:

1. Keep the tax total sourced from `purchase_tax_line.amount`.
2. Prefer separate tax postings in the ledger.
3. Use line-level tax-code-driven logic only when line attribution is required and you can support it with enough tax metadata.
4. If line-level calculation is introduced, reconcile the calculated total back to `purchase_tax_line.amount`.
5. Prefer actual line tax amounts if the raw connector provides them.

## Practical Recommendation for This Package

For this dbt package specifically, the strongest long-term approach is likely:

- bookkeeping-first in the general ledger
- optional line-level tax calculation for analytical models when needed

That can work especially well if the implementation follows this pattern:

1. Keep the official ledger tax total tied to `purchase_tax_line.amount`.
2. Add tax-code-based line calculation only for distributing tax across lines.
3. Reconcile the sum of calculated line tax back to the posted purchase tax total.
4. If there is a mismatch, prefer the posted tax total over the recalculated amount.

That gives the package a more reliable accounting foundation while still allowing richer downstream reporting.
