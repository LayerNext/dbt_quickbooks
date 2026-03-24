{{ config(enabled=var('using_purchase_tax_line', False)) }}

with line_tax_calc as (

    select *
    from {{ ref('int_quickbooks__purchase_line_tax_calc') }}
),

posted_purchase_tax as (

    select
        purchase_id,
        source_relation,
        sum(amount) as posted_tax_total,
        min(tax_rate_id) as posted_tax_rate_id
    from {{ ref('stg_quickbooks__purchase_tax_line') }}
    group by 1, 2
),

calculated_purchase_tax as (

    select
        purchase_id,
        source_relation,
        sum(provisional_tax_amount) as calculated_tax_total
    from line_tax_calc
    where provisional_tax_amount is not null
    group by 1, 2
),

first_eligible_line as (

    select
        purchase_id,
        source_relation,
        purchase_line_index,
        expense_account_id,
        class_id,
        tax_row_index
    from (
        select
            line_tax_calc.*,
            row_number() over (
                partition by purchase_id, source_relation
                order by
                    case when is_taxable then 0 else 1 end,
                    purchase_line_index
            ) as row_num
        from line_tax_calc
        where expense_account_id is not null
    ) ranked
    where row_num = 1
),

final as (

    select
        posted_purchase_tax.purchase_id,
        posted_purchase_tax.source_relation,
        coalesce(calculated_purchase_tax.calculated_tax_total, 0) as calculated_tax_total,
        posted_purchase_tax.posted_tax_total,
        posted_purchase_tax.posted_tax_total - coalesce(calculated_purchase_tax.calculated_tax_total, 0) as tax_difference,
        first_eligible_line.purchase_line_index as fallback_purchase_line_index,
        first_eligible_line.expense_account_id as fallback_expense_account_id,
        first_eligible_line.class_id as fallback_class_id,
        {{ dbt.concat(["'fallback:'", "coalesce(first_eligible_line.purchase_line_index, '0')", "':tax'"]) }} as fallback_tax_row_index,
        posted_purchase_tax.posted_tax_rate_id,
        case
            when calculated_purchase_tax.calculated_tax_total is null and first_eligible_line.purchase_line_index is not null
                then 'fallback_posted_purchase_tax'
            when abs(posted_purchase_tax.posted_tax_total - coalesce(calculated_purchase_tax.calculated_tax_total, 0)) <= 0.01
                and abs(posted_purchase_tax.posted_tax_total - coalesce(calculated_purchase_tax.calculated_tax_total, 0)) > 0
                then 'rounded_adjustment'
            when abs(posted_purchase_tax.posted_tax_total - coalesce(calculated_purchase_tax.calculated_tax_total, 0)) <= 0.01
                then 'reconciled'
            when first_eligible_line.purchase_line_index is not null
                then 'fallback_posted_purchase_tax'
            else 'unresolved_no_eligible_line'
        end as reconciliation_status
    from posted_purchase_tax

    left join calculated_purchase_tax
        on posted_purchase_tax.purchase_id = calculated_purchase_tax.purchase_id
        and posted_purchase_tax.source_relation = calculated_purchase_tax.source_relation

    left join first_eligible_line
        on posted_purchase_tax.purchase_id = first_eligible_line.purchase_id
        and posted_purchase_tax.source_relation = first_eligible_line.source_relation
)

select *
from final
