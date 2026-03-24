--To enable this model, set the using_tax_code variable within your dbt_project.yml file to True.
{{ config(enabled=var('using_tax_code', False)) }}

with base as (

    select *
    from {{ ref('stg_quickbooks__tax_code_tmp') }}

),

fields as (

    select
        {{
            fivetran_utils.fill_staging_columns(
                source_columns=adapter.get_columns_in_relation(ref('stg_quickbooks__tax_code_tmp')),
                staging_columns=get_tax_code_columns()
            )
        }}

        {{
            fivetran_utils.source_relation(
                union_schema_variable='quickbooks_union_schemas',
                union_database_variable='quickbooks_union_databases'
            )
        }}
    from base
),

final as (

    select
        cast(id as {{ dbt.type_string() }}) as tax_code_id,
        active,
        created_at,
        description,
        name as tax_code_name,
        cast(purchase_tax_rate_id as {{ dbt.type_string() }}) as purchase_tax_rate_id,
        cast(sales_tax_rate_id as {{ dbt.type_string() }}) as sales_tax_rate_id,
        taxable,
        updated_at,
        source_relation
    from fields
)

select *
from final
where not coalesce(_fivetran_deleted, false)
