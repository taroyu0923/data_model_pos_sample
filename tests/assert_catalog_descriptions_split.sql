{{ config(severity='warn') }}
-- Warn when a real catalog item fell into category 'Unknown' because its description had no ' - ' or ' | ' separator.
select item_code, item_category, item_category_sub
from {{ ref('stg_catalog') }}
where item_category = 'Unknown'
    and item_code <> 'UNKNOWN_ITEM'
