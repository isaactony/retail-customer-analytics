-- Grain: acquisition cohort (month of first order) × months since first order.
-- How many of each cohort ordered again in each later month, and what they were worth.

with cohort_sizes as (
    select cohort_month, count(*) as cohort_customers
    from {{ ref('dim_customer') }}
    group by 1
),

activity as (
    select
        c.cohort_month,
        (extract(year from o.order_month) * 12 + extract(month from o.order_month))
          - (extract(year from c.cohort_month) * 12 + extract(month from c.cohort_month)) as months_since_first,
        count(distinct o.customer_key)  as active_customers,
        sum(o.net_revenue_usd)          as net_revenue_usd,
        sum(o.gross_margin_usd)         as gross_margin_usd
    from {{ ref('fct_orders') }} as o
    join {{ ref('dim_customer') }} as c using (customer_key)
    group by 1, 2
)

select
    a.cohort_month,
    extract(year from a.cohort_month)::int                       as cohort_year,
    a.months_since_first::int                                    as months_since_first,
    s.cohort_customers,
    a.active_customers,
    round(a.active_customers::numeric / s.cohort_customers, 4)   as retention_rate,
    a.net_revenue_usd,
    a.gross_margin_usd,
    round(sum(a.net_revenue_usd) over w / s.cohort_customers, 2)  as cumulative_revenue_per_customer_usd,
    round(sum(a.gross_margin_usd) over w / s.cohort_customers, 2) as cumulative_margin_per_customer_usd,
    -- a cohort-month is only complete if the whole month is inside the extract
    (a.cohort_month + make_interval(months => a.months_since_first::int + 1))::date
        <= '{{ var("analysis_date") }}'::date + 1                as is_complete_period
from activity as a
join cohort_sizes as s using (cohort_month)
window w as (partition by a.cohort_month order by a.months_since_first)
