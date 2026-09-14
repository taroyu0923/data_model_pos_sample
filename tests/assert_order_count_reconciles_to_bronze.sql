-- Every distinct raw transaction appears exactly once in fct_orders.
with bronze as (
    select count(distinct trim(tx_id)) as n from {{ ref('brz_pos_system') }}
),

gold as (
    select count(*) as n from {{ ref('fct_orders') }}
)

select bronze.n as bronze_orders, gold.n as gold_orders
from bronze, gold
where bronze.n <> gold.n
