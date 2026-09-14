-- Order revenue must equal the sum of its line revenue.
select
    o.tx_id,
    o.order_revenue,
    sum(i.line_revenue) as line_total
from {{ ref('fct_orders') }} as o
inner join {{ ref('fct_order_items') }} as i
    on o.tx_id = i.tx_id
group by o.tx_id, o.order_revenue
having o.order_revenue <> sum(i.line_revenue)
