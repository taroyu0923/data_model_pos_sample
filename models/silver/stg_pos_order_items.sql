-- Grain: one row per (tx_id, item_code). items_sold split on '|', "<qty>x <code>" parsed; repeats of a code summed.
with tokens as (
    select
        trim(tx_id) as tx_id,
        trim(unnest(string_split(items_sold, '|'))) as item_token
    from {{ ref('brz_pos_system') }}
),

parsed as (
    select
        tx_id,
        try_cast(regexp_extract(item_token, '^(-?\d+)\s*x\s+(\S+)$', 1) as integer) as quantity,
        upper(regexp_extract(item_token, '^(-?\d+)\s*x\s+(\S+)$', 2)) as item_code
    from tokens
)

select
    tx_id,
    nullif(item_code, '') as item_code,
    cast(sum(quantity) as integer) as quantity
from parsed
group by tx_id, item_code
