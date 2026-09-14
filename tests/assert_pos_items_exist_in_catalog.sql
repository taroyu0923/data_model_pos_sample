{{ config(severity='warn') }}
-- Warn (not fail) when the POS sells a code missing from the catalog; Gold maps it to UNKNOWN_ITEM.
select distinct
    l.tx_id,
    l.item_code
from {{ ref('stg_pos_order_items') }} as l
left join {{ ref('stg_catalog') }} as c
    on l.item_code = c.item_code
where c.item_code is null
