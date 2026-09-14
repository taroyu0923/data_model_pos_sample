-- Grain: one row per source customer record (history kept). is_latest marks the record dim_customer uses.
with source as (
    select
        case when lower(trim(cust_email)) in ('', 'null') then null else lower(trim(cust_email)) end as cust_email,
        trim(full_name) as raw_full_name,
        trim(tier) as raw_tier,
        try_cast(trim(updated_at) as timestamp) as updated_at
    from {{ ref('brz_customers') }}
),

cleaned as (
    select
        cust_email,
        {{ title_case("case when raw_full_name like '%,%'
                then split_part(raw_full_name, ',', 2) || ' ' || split_part(raw_full_name, ',', 1)
                else raw_full_name end") }} as full_name,
        case
            when raw_tier is null or upper(raw_tier) in ('', 'NONE') then 'None'
            else {{ title_case('raw_tier') }}
        end as tier,
        updated_at
    from source
)

select
    cust_email,
    full_name,
    tier,
    updated_at,
    cust_email is not null
        and row_number() over (partition by cust_email order by updated_at desc nulls last, full_name, tier) = 1
        as is_latest
from cleaned
