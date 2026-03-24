{% macro get_tax_code_columns() %}

{% set columns = [
    {"name": "_fivetran_deleted", "datatype": dbt.type_boolean()},
    {"name": "_fivetran_synced", "datatype": dbt.type_timestamp()},
    {"name": "active", "datatype": dbt.type_boolean()},
    {"name": "created_at", "datatype": dbt.type_timestamp()},
    {"name": "description", "datatype": dbt.type_string()},
    {"name": "id", "datatype": dbt.type_string()},
    {"name": "name", "datatype": dbt.type_string()},
    {"name": "purchase_tax_rate_id", "datatype": dbt.type_string()},
    {"name": "sales_tax_rate_id", "datatype": dbt.type_string()},
    {"name": "taxable", "datatype": dbt.type_boolean()},
    {"name": "updated_at", "datatype": dbt.type_timestamp()}
] %}

{{ return(columns) }}

{% endmacro %}
