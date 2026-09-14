-- Grain: one row per item_code (includes UNKNOWN_ITEM, used for POS codes missing from the catalog).
select
    item_code,
    item_category,
    item_category_sub,
    unit_price
from {{ ref('stg_catalog') }}
