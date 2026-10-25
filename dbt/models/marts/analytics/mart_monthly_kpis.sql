-- Grain: month × channel × customer country. The headline commercial numbers.

with orders as (
    select o.*, c.country as customer_country
    from {{ ref('fct_orders') }} as o
    join {{ ref('dim_customer') }} as c using (customer_key)
)

select
    order_month,
    channel,
    customer_country,
    count(*)                                                    as orders,
    count(distinct customer_key)                                as customers,
    count(distinct customer_key) filter (where is_first_order)  as new_customers,
    count(distinct customer_key) filter (where not is_first_order) as returning_customers,
    sum(item_count)                                             as items,
    sum(gross_sales_usd)                                        as gross_sales_usd,
    sum(discount_usd)                                           as discount_usd,
    sum(net_revenue_usd)                                        as net_revenue_usd,
    sum(gross_margin_usd)                                       as gross_margin_usd
from orders
group by 1, 2, 3
