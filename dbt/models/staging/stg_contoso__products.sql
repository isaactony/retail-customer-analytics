select
    product_key::int            as product_key,
    product_code,
    product_name,
    manufacturer,
    brand,
    color,
    category_key::int           as category_key,
    category_name               as category,
    sub_category_key::int       as subcategory_key,
    sub_category_name           as subcategory,
    cost::numeric               as list_cost_usd,
    price::numeric              as list_price_usd
from {{ source('raw', 'product') }}
