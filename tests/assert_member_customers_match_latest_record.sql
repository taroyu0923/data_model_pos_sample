-- Every non-null Silver email appears exactly once in dim_customer as a member, with the newest updated_at;
-- and no member exists without a Silver email. Uses max() instead of the model's row_number().
with expected as (
    select cust_email, max(updated_at) as updated_at
    from {{ ref('stg_customers') }}
    where cust_email is not null
    group by cust_email
),

members as (
    select customer_id, updated_at
    from {{ ref('dim_customer') }}
    where customer_type = 'member'
)

select e.cust_email as problem_id, 'missing or stale member' as problem
from expected as e
left join members as m
    on m.customer_id = e.cust_email
where m.customer_id is null
    or m.updated_at <> e.updated_at

union all

select m.customer_id as problem_id, 'member without Silver email' as problem
from members as m
where not exists (select 1 from expected as e where e.cust_email = m.customer_id)
