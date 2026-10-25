-- fct_order_lines is built from raw.sales; raw.orderrows is a second, independent copy of the
-- same lines. Net revenue must agree to the cent.

with modelled as (select sum(net_revenue_usd) as v from {{ ref('fct_order_lines') }}),
     independent as (select sum(quantity::int * net_price::numeric) as v from {{ source('raw', 'orderrows') }})

select m.v as modelled_usd, i.v as orderrows_usd
from modelled as m, independent as i
where abs(m.v - i.v) > 0.01
