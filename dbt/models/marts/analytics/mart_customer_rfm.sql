-- Grain: one row per customer. Recency / frequency / monetary scores (1 = lowest, 5 = highest)
-- as of the analysis date, mapped to named segments with a recommended action (seed: rfm_segments).

with scored as (
    select
        c.customer_key,
        c.country,
        c.acquisition_channel,
        c.cohort_year,
        c.days_since_last_order                                         as recency_days,
        c.lifetime_orders                                               as frequency,
        c.lifetime_revenue_usd                                          as monetary_usd,
        c.lifetime_gross_margin_usd,
        ntile(5) over (order by c.days_since_last_order desc, c.customer_key)       as recency_score,
        ntile(5) over (order by c.lifetime_orders, c.customer_key)                  as frequency_score,
        ntile(5) over (order by c.lifetime_revenue_usd, c.customer_key)             as monetary_score
    from {{ ref('dim_customer') }} as c
)

select
    s.*,
    s.recency_score::text || s.frequency_score::text || s.monetary_score::text as rfm_code,
    seg.segment,
    seg.segment_order,
    seg.recommended_action
from scored as s
join {{ ref('rfm_segments') }} as seg
  on seg.recency_score = s.recency_score and seg.frequency_score = s.frequency_score
