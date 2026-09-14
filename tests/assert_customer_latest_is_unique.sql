-- Exactly one is_latest record per non-null email.
select
    cust_email,
    count(*) filter (where is_latest) as latest_records
from {{ ref('stg_customers') }}
where cust_email is not null
group by cust_email
having count(*) filter (where is_latest) <> 1
