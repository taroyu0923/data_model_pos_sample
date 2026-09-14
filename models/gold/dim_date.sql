-- Grain: one row per calendar day from the first to the last sale date.
with bounds as (
    select
        min(cast(sale_timestamp as date)) as first_day,
        max(cast(sale_timestamp as date)) as last_day
    from {{ ref('stg_pos_orders') }}
),

days as (
    select cast(unnest(generate_series(first_day, last_day, interval 1 day)) as date) as date_day
    from bounds
)

select
    date_day,
    cast(year(date_day) as integer) as year,
    cast(month(date_day) as integer) as month,
    monthname(date_day) as month_name,
    cast(date_trunc('week', date_day) as date) as week_start_date,
    cast(isodow(date_day) as integer) as day_of_week,
    dayname(date_day) as day_name,
    isodow(date_day) in (6, 7) as is_weekend
from days
