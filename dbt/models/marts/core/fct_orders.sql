{{ config(indexes=[{'columns': ['order_key'], 'unique': true}, {'columns': ['customer_key']}, {'columns': ['order_date']}]) }}

-- Grain: one row per order. Money in USD unless the column says otherwise.

select
    order_key,
    customer_key,
    store_key,
    order_date,
    date_trunc('month', order_date)::date       as order_month,
    delivery_date,
    delivery_days,
    channel,
    currency_code,
    line_count,
    item_count,
    gross_sales_usd,
    discount_usd,
    net_revenue_usd,
    cost_usd,
    gross_margin_usd,
    net_revenue_order_currency,
    customer_order_number,
    customer_order_number = 1                   as is_first_order,
    previous_order_date,
    days_since_previous_order
from {{ ref('int_orders_enriched') }}
