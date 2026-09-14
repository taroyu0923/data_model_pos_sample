-- Grain: one row per item_code. Codes upper-cased; description split into category / sub-category; price cast.
with source as (
    select
        upper(trim(item_code)) as item_code,
        trim(description) as description,
        try_cast(nullif(regexp_replace(unit_price, '[$\s]', '', 'g'), '') as decimal(10, 2)) as unit_price
    from {{ ref('brz_catalog') }}
)

select
    item_code,
    case
        when regexp_matches(description, '\s[-|]\s') then trim(regexp_extract(description, '^(.*?)\s[-|]\s', 1))
        else 'Unknown'
    end as item_category,
    case
        when regexp_matches(description, '\s[-|]\s') then trim(regexp_extract(description, '\s[-|]\s(.*)$', 1))
        else description
    end as item_category_sub,
    unit_price
from source
