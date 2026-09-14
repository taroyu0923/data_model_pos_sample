-- Grain: one row per item_code. Always contains UNKNOWN_ITEM (added here if the catalog lacks it),
-- because fct_order_items maps POS codes missing from the catalog to it.
with catalog as (
    select
        item_code,
        item_category,
        item_category_sub,
        unit_price
    from {{ ref('stg_catalog') }}
)

select * from catalog
union all
select
    'UNKNOWN_ITEM' as item_code,
    'Unknown' as item_category,
    'Unknown' as item_category_sub,
    cast(0 as decimal(10, 2)) as unit_price
where not exists (select 1 from catalog where item_code = 'UNKNOWN_ITEM')
