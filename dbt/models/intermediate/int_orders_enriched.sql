-- One row per order: line totals rolled up, plus where the order sits in its customer's history.

with line_totals as (
    select
        order_key,
        count(*)                        as line_count,
        sum(quantity)                   as item_count,
        sum(gross_sales_usd)            as gross_sales_usd,
        sum(discount_usd)               as discount_usd,
        sum(net_revenue_usd)            as net_revenue_usd,
        sum(cost_usd)                   as cost_usd,
        sum(gross_margin_usd)           as gross_margin_usd,
        sum(net_revenue_order_currency) as net_revenue_order_currency
    from {{ ref('stg_contoso__order_lines') }}
    group by 1
),

orders as (
    select
        o.*,
        s.is_online,
        case when s.is_online then 'Online' else 'Store' end as channel,
        t.line_count, t.item_count, t.gross_sales_usd, t.discount_usd, t.net_revenue_usd,
        t.cost_usd, t.gross_margin_usd, t.net_revenue_order_currency
    from {{ ref('stg_contoso__orders') }} as o
    join {{ ref('stg_contoso__stores') }} as s using (store_key)
    join line_totals as t using (order_key)
)

select
    *,
    delivery_date - order_date                                              as delivery_days,
    row_number() over (partition by customer_key order by order_date, order_key)   as customer_order_number,
    lag(order_date) over (partition by customer_key order by order_date, order_key) as previous_order_date,
    order_date - lag(order_date) over (partition by customer_key order by order_date, order_key)
                                                                            as days_since_previous_order
from orders
