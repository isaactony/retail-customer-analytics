-- One row per customer who has ordered. Acquisition = their first order.

with history as (
    select
        customer_key,
        min(order_date)                                         as first_order_date,
        max(order_date)                                         as last_order_date,
        count(*)                                                as lifetime_orders,
        sum(net_revenue_usd)                                    as lifetime_revenue_usd,
        sum(gross_margin_usd)                                   as lifetime_gross_margin_usd,
        count(*) filter (where is_online)                       as online_orders
    from {{ ref('int_orders_enriched') }}
    group by 1
),

first_order as (
    select customer_key, channel as acquisition_channel, store_key as first_store_key
    from {{ ref('int_orders_enriched') }}
    where customer_order_number = 1
)

select
    c.customer_key,
    c.continent,
    c.country_code,
    c.country,
    c.state,
    c.gender,
    c.birth_year,
    case
        when extract(year from h.first_order_date) - c.birth_year < 25 then '18–24'
        when extract(year from h.first_order_date) - c.birth_year < 35 then '25–34'
        when extract(year from h.first_order_date) - c.birth_year < 45 then '35–44'
        when extract(year from h.first_order_date) - c.birth_year < 55 then '45–54'
        when extract(year from h.first_order_date) - c.birth_year < 65 then '55–64'
        else '65+'
    end                                                         as age_band_at_first_order,
    h.first_order_date,
    date_trunc('month', h.first_order_date)::date               as cohort_month,
    extract(year from h.first_order_date)::int                  as cohort_year,
    f.acquisition_channel,
    f.first_store_key,
    h.last_order_date,
    h.lifetime_orders,
    h.lifetime_revenue_usd,
    h.lifetime_gross_margin_usd,
    round(h.online_orders::numeric / h.lifetime_orders, 4)      as online_order_share,
    '{{ var("analysis_date") }}'::date - h.last_order_date      as days_since_last_order,
    '{{ var("analysis_date") }}'::date - h.last_order_date <= {{ var("lapsed_after_days") }}
                                                                as is_active
from {{ ref('stg_contoso__customers') }} as c
join history as h using (customer_key)
join first_order as f using (customer_key)
