-- Grain: store × year. Physical stores also get revenue per square metre.

select
    s.store_key,
    s.store_name,
    s.country,
    s.is_online,
    s.status,
    s.close_date,
    s.square_meters,
    extract(year from o.order_date)::int                            as year,
    count(*)                                                        as orders,
    count(distinct o.customer_key)                                  as customers,
    sum(o.net_revenue_usd)                                          as net_revenue_usd,
    sum(o.gross_margin_usd)                                         as gross_margin_usd,
    round(sum(o.net_revenue_usd) / count(*), 2)                     as avg_order_value_usd,
    round(sum(o.net_revenue_usd) / nullif(s.square_meters, 0), 2)   as revenue_per_sqm_usd
from {{ ref('fct_orders') }} as o
join {{ ref('dim_store') }} as s using (store_key)
group by s.store_key, s.store_name, s.country, s.is_online, s.status, s.close_date, s.square_meters, 8
