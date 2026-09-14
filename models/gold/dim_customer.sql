-- Grain: one row per customer_id. Latest record per email (member), POS emails not in the loyalty list
-- (inferred), plus the sentinel rows __guest__ and __unknown__ so every sale joins to a customer.
with members as (
    select
        cust_email as customer_id,
        cust_email,
        full_name,
        tier,
        updated_at,
        'member' as customer_type
    from {{ ref('stg_customers') }}
    where is_latest
),

inferred as (
    select
        o.customer_contact as customer_id,
        o.customer_contact as cust_email,
        'Unknown' as full_name,
        'None' as tier,
        min(o.sale_timestamp) as updated_at,
        'inferred' as customer_type
    from {{ ref('stg_pos_orders') }} as o
    where o.contact_type = 'email'
        and not exists (select 1 from members as m where m.customer_id = o.customer_contact)
    group by o.customer_contact
),

sentinels as (
    select * from (values
        ('__guest__', null, 'Guest', 'None', null, 'guest'),
        ('__unknown__', null, 'Unknown', 'None', null, 'unknown')
    ) as t (customer_id, cust_email, full_name, tier, updated_at, customer_type)
)

select * from members
union all
select * from inferred
union all
select
    customer_id,
    cast(cust_email as varchar),
    full_name,
    tier,
    cast(updated_at as timestamp),
    customer_type
from sentinels
