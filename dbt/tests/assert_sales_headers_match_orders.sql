-- raw.sales repeats the order header on every line. It must match raw.orders exactly,
-- or the model would mix two versions of the same order.

select s.order_key, s.line_number
from {{ source('raw', 'sales') }} as s
left join {{ source('raw', 'orders') }} as o using (order_key)
where o.order_key is null
   or o.customer_key <> s.customer_key
   or o.store_key <> s.store_key
   or o.order_date <> s.order_date
   or o.currency_code <> s.currency_code
