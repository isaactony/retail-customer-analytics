-- One row per order line. Prices are in USD; exchange_rate converts USD into the order's currency.

with lines as (
    select
        order_key::bigint           as order_key,
        line_number::int            as line_number,
        product_key::int            as product_key,
        quantity::int               as quantity,
        unit_price::numeric         as unit_price_usd,      -- price before discount
        net_price::numeric          as net_price_usd,       -- price actually charged
        unit_cost::numeric          as unit_cost_usd,
        currency_code,
        exchange_rate::numeric      as usd_to_order_currency
    from {{ source('raw', 'sales') }}
)

select
    *,
    quantity * unit_price_usd                               as gross_sales_usd,
    quantity * net_price_usd                                as net_revenue_usd,
    quantity * (unit_price_usd - net_price_usd)             as discount_usd,
    quantity * unit_cost_usd                                as cost_usd,
    quantity * (net_price_usd - unit_cost_usd)              as gross_margin_usd,
    quantity * net_price_usd * usd_to_order_currency        as net_revenue_order_currency
from lines
