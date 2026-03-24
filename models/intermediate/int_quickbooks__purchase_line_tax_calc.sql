{{ config(enabled=var('using_purchase_tax_line', False)) }}

{% set using_tax_code = var('using_tax_code', False) %}
{% set using_tax_rate = var('using_tax_rate', False) %}
{% set using_tax_rate_detail = var('using_tax_rate_detail', False) %}

with purchase_lines as (

    select *
    from {{ ref('stg_quickbooks__purchase_line') }}
),

items as (

    select
        item.*,
        parent.expense_account_id as parent_expense_account_id
    from {{ ref('stg_quickbooks__item') }} item

    left join {{ ref('stg_quickbooks__item') }} parent
        on item.parent_item_id = parent.item_id
        and item.source_relation = parent.source_relation
),

{% if using_tax_code %}
tax_codes as (

    select *
    from {{ ref('stg_quickbooks__tax_code') }}
),
{% endif %}

{% if using_tax_rate_detail %}
tax_rate_details as (

    select *
    from {{ ref('stg_quickbooks__tax_rate_detail') }}
),

tax_rate_details_agg as (

    select
        tax_code_id,
        source_relation,
        min(tax_rate_id) as tax_rate_id,
        sum(coalesce(rate_value, 0)) as combined_rate_value
    from tax_rate_details
    group by 1, 2
),
{% endif %}

{% if using_tax_rate %}
tax_rates as (

    select *
    from {{ ref('stg_quickbooks__tax_rate') }}
),
{% endif %}

resolved_lines as (

    select
        purchase_lines.purchase_id,
        purchase_lines.source_relation,
        cast(purchase_lines.index as {{ dbt.type_string() }}) as purchase_line_index,
        {{ dbt.concat(["cast(purchase_lines.index as " ~ dbt.type_string() ~ ")", "':tax'"]) }} as tax_row_index,
        coalesce(
            purchase_lines.account_expense_account_id,
            items.parent_expense_account_id,
            items.expense_account_id
        ) as expense_account_id,
        coalesce(
            purchase_lines.item_expense_class_id,
            purchase_lines.account_expense_class_id
        ) as class_id,
        purchase_lines.amount as line_amount,
        purchase_lines.account_expense_tax_amount as explicit_tax_amount,
        coalesce(
            purchase_lines.account_expense_tax_code_id,
            purchase_lines.item_expense_tax_code_id
        ) as tax_code_id
    from purchase_lines

    left join items
        on purchase_lines.item_expense_item_id = items.item_id
        and purchase_lines.source_relation = items.source_relation
),

configured_lines as (

    select
        resolved_lines.*,
        {% if using_tax_code %}
        tax_codes.purchase_tax_rate_id as tax_code_purchase_rate_id,
        {% else %}
        cast(null as {{ dbt.type_string() }}) as tax_code_purchase_rate_id,
        {% endif %}
        {% if using_tax_rate_detail %}
        tax_rate_details_agg.tax_rate_id as detail_tax_rate_id,
        tax_rate_details_agg.combined_rate_value as detail_rate_value,
        {% else %}
        cast(null as {{ dbt.type_string() }}) as detail_tax_rate_id,
        cast(null as {{ dbt.type_numeric() }}) as detail_rate_value,
        {% endif %}
        {% if using_tax_rate_detail and using_tax_code %}
        coalesce(tax_rate_details_agg.tax_rate_id, tax_codes.purchase_tax_rate_id) as derived_tax_rate_id
        {% elif using_tax_rate_detail %}
        tax_rate_details_agg.tax_rate_id as derived_tax_rate_id
        {% elif using_tax_code %}
        tax_codes.purchase_tax_rate_id as derived_tax_rate_id
        {% else %}
        cast(null as {{ dbt.type_string() }}) as derived_tax_rate_id
        {% endif %}
    from resolved_lines

    {% if using_tax_code %}
    left join tax_codes
        on resolved_lines.tax_code_id = tax_codes.tax_code_id
        and resolved_lines.source_relation = tax_codes.source_relation
    {% endif %}

    {% if using_tax_rate_detail %}
    left join tax_rate_details_agg
        on resolved_lines.tax_code_id = tax_rate_details_agg.tax_code_id
        and resolved_lines.source_relation = tax_rate_details_agg.source_relation
    {% endif %}
),

final as (

    select
        configured_lines.purchase_id,
        configured_lines.source_relation,
        configured_lines.purchase_line_index,
        configured_lines.tax_row_index,
        configured_lines.expense_account_id,
        configured_lines.class_id,
        configured_lines.line_amount,
        case
            when configured_lines.explicit_tax_amount is not null then configured_lines.explicit_tax_amount
            when configured_lines.tax_code_id is not null and configured_lines.line_amount is not null then
                configured_lines.line_amount
                *
                (
                    {% if using_tax_rate %}
                    coalesce(
                        cast(tax_rates.effective_tax_rate as {{ dbt.type_float() }}),
                        tax_rates.rate_value,
                        configured_lines.detail_rate_value
                    )
                    {% else %}
                    configured_lines.detail_rate_value
                    {% endif %}
                ) / 100.0
            else cast(null as {{ dbt.type_numeric() }})
        end as provisional_tax_amount,
        configured_lines.tax_code_id,
        configured_lines.derived_tax_rate_id as tax_rate_id,
        case
            when configured_lines.explicit_tax_amount is not null then 'purchase_line_tax_amount'
            when configured_lines.tax_code_id is not null and (
                {% if using_tax_rate %}
                tax_rates.effective_tax_rate is not null
                or tax_rates.rate_value is not null
                {% else %}
                false
                {% endif %}
                {% if using_tax_rate_detail %}
                or configured_lines.detail_rate_value is not null
                {% endif %}
            ) then 'tax_code_rate'
            when configured_lines.tax_code_id is not null then 'tax_code_unresolved'
            else 'no_tax_code'
        end as tax_calc_method,
        case
            when configured_lines.explicit_tax_amount is not null or configured_lines.tax_code_id is not null
                then true
            else false
        end as is_taxable
    from configured_lines

    {% if using_tax_rate %}
    left join tax_rates
        on configured_lines.derived_tax_rate_id = tax_rates.tax_rate_id
        and configured_lines.source_relation = tax_rates.source_relation
    {% endif %}
)

select *
from final
