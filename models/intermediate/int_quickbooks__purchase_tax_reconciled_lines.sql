{{ config(enabled=var('using_purchase_tax_line', False)) }}

with line_tax_calc as (

    select *
    from {{ ref('int_quickbooks__purchase_line_tax_calc') }}
),

purchase_tax_reconciliation as (

    select *
    from {{ ref('int_quickbooks__purchase_tax_reconciliation') }}
),

reconciled_line_rows as (

    select
        line_tax_calc.purchase_id,
        line_tax_calc.source_relation,
        line_tax_calc.purchase_line_index,
        line_tax_calc.tax_row_index,
        line_tax_calc.expense_account_id,
        line_tax_calc.class_id,
        case
            when row_number() over (
                partition by line_tax_calc.purchase_id, line_tax_calc.source_relation
                order by line_tax_calc.purchase_line_index
            ) = 1
                then line_tax_calc.provisional_tax_amount + purchase_tax_reconciliation.tax_difference
            else line_tax_calc.provisional_tax_amount
        end as final_tax_amount,
        coalesce(line_tax_calc.tax_rate_id, purchase_tax_reconciliation.posted_tax_rate_id) as tax_rate_id,
        line_tax_calc.tax_calc_method,
        false as is_fallback_row
    from line_tax_calc

    inner join purchase_tax_reconciliation
        on line_tax_calc.purchase_id = purchase_tax_reconciliation.purchase_id
        and line_tax_calc.source_relation = purchase_tax_reconciliation.source_relation

    where purchase_tax_reconciliation.reconciliation_status in ('reconciled', 'rounded_adjustment')
        and line_tax_calc.provisional_tax_amount is not null
),

fallback_rows as (

    select
        purchase_id,
        source_relation,
        fallback_purchase_line_index as purchase_line_index,
        fallback_tax_row_index as tax_row_index,
        fallback_expense_account_id as expense_account_id,
        fallback_class_id as class_id,
        posted_tax_total as final_tax_amount,
        posted_tax_rate_id as tax_rate_id,
        'fallback_posted_purchase_tax' as tax_calc_method,
        true as is_fallback_row
    from purchase_tax_reconciliation
    where reconciliation_status = 'fallback_posted_purchase_tax'
),

final as (

    select *
    from reconciled_line_rows

    union all

    select *
    from fallback_rows
)

select *
from final
where final_tax_amount is not null
    and final_tax_amount != 0
