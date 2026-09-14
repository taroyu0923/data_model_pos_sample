{{ config(severity='warn') }}
-- Decision C nets repeated codes in one transaction into one line. If the same item is both sold and returned
-- in one transaction, the return disappears from Units Returned. Warn so it is visible.
with tokens as (
    select
        trim(tx_id) as tx_id,
        trim(unnest(string_split(items_sold, '|'))) as item_token
    from {{ ref('brz_pos_system') }}
),

parsed as (
    select
        tx_id,
        upper(regexp_extract(item_token, '^(-?\d+)\s*[xX]\s+(\S+)$', 2)) as item_code,
        try_cast(regexp_extract(item_token, '^(-?\d+)\s*[xX]\s+(\S+)$', 1) as integer) as quantity
    from tokens
)

select tx_id, item_code
from parsed
group by tx_id, item_code
having min(quantity) < 0 and max(quantity) > 0
