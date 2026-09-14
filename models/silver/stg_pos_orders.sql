-- Grain: one row per tx_id. Timestamp parsed from two formats; contact classified; store JSON extracted.
with source as (
    select
        trim(tx_id) as tx_id,
        trim(sale_timestamp) as raw_sale_timestamp,
        case when trim(customer_contact) = '' then null else lower(trim(customer_contact)) end as customer_contact,
        store_metadata
    from {{ ref('brz_pos_system') }}
)

select
    tx_id,
    coalesce(
        try_strptime(raw_sale_timestamp, '%m/%d/%Y %H:%M'),
        try_strptime(raw_sale_timestamp, '%Y-%m-%d %H:%M:%S')
    ) as sale_timestamp,
    customer_contact,
    case
        when customer_contact is null then 'guest'
        when regexp_full_match(customer_contact, '[^@\s]+@[^@\s]+\.[^@\s]+') then 'email'
        else 'invalid'
    end as contact_type,
    trim(json_extract_string(store_metadata, '$.store_id')) as store_id,
    {{ title_case("json_extract_string(store_metadata, '$.city')") }} as city,
    upper(trim(json_extract_string(store_metadata, '$.region'))) as region
from source
