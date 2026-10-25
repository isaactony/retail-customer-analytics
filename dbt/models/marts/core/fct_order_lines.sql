{{ config(indexes=[{'columns': ['order_key', 'line_number'], 'unique': true}, {'columns': ['product_key']}]) }}

-- Grain: one row per order line.

select
    l.order_key,
    l.line_number,
    o.customer_key,
    o.store_key,
    o.order_date,
    o.channel,
    l.product_key,
    l.quantity,
    l.unit_price_usd,
    l.net_price_usd,
    l.unit_cost_usd,
    l.gross_sales_usd,
    l.discount_usd,
    l.net_revenue_usd,
    l.cost_usd,
    l.gross_margin_usd
from {{ ref('stg_contoso__order_lines') }} as l
join {{ ref('int_orders_enriched') }} as o using (order_key)
