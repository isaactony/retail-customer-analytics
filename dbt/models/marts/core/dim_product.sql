select
    *,
    round(1 - list_cost_usd / nullif(list_price_usd, 0), 4) as list_margin_pct
from {{ ref('stg_contoso__products') }}
