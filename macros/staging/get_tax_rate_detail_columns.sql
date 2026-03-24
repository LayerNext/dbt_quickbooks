{% macro get_tax_rate_detail_columns() %}

{% set columns = [
    {"name": "_fivetran_deleted", "datatype": dbt.type_boolean()},
    {"name": "_fivetran_synced", "datatype": dbt.type_timestamp()},
    {"name": "created_at", "datatype": dbt.type_timestamp()},
    {"name": "id", "datatype": dbt.type_string()},
    {"name": "rate_value", "datatype": dbt.type_float()},
    {"name": "tax_code_id", "datatype": dbt.type_string()},
    {"name": "tax_order", "datatype": dbt.type_int()},
    {"name": "tax_rate_id", "datatype": dbt.type_string()},
    {"name": "updated_at", "datatype": dbt.type_timestamp()}
] %}

{{ return(columns) }}

{% endmacro %}
