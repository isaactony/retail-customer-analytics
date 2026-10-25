select
    order_key::bigint                       as order_key,
    customer_key::bigint                    as customer_key,
    store_key::int                          as store_key,
    order_date::date                        as order_date,
    delivery_date::date                     as delivery_date,
    currency_code
from {{ source('raw', 'orders') }}
