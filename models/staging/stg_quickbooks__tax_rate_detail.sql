--To enable this model, set the using_tax_rate_detail variable within your dbt_project.yml file to True.
{{ config(enabled=var('using_tax_rate_detail', False)) }}

with base as (

    select *
    from {{ ref('stg_quickbooks__tax_rate_detail_tmp') }}

),

fields as (

    select
        {{
            fivetran_utils.fill_staging_columns(
                source_columns=adapter.get_columns_in_relation(ref('stg_quickbooks__tax_rate_detail_tmp')),
                staging_columns=get_tax_rate_detail_columns()
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
        cast(id as {{ dbt.type_string() }}) as tax_rate_detail_id,
        cast(tax_code_id as {{ dbt.type_string() }}) as tax_code_id,
        cast(tax_rate_id as {{ dbt.type_string() }}) as tax_rate_id,
        rate_value,
        tax_order,
        created_at,
        updated_at,
        source_relation
    from fields
)

select *
from final
where not coalesce(_fivetran_deleted, false)
