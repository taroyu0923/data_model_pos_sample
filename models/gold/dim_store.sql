-- Grain: one row per store_id, extracted from POS store_metadata. Conflicting attributes fail the unique test.
select distinct
    store_id,
    city,
    region
from {{ ref('stg_pos_orders') }}
