-- What happened to a store's customers after it closed? For each store that closed during the
-- extract: customers who ordered there in the 12 months before closing, and whether they ordered
-- again anywhere in the 12 months after (online, another store, or not at all).

with closed as (
    select store_key, store_name, country, close_date
    from {{ ref('dim_store') }}
    where closed_during_extract and not is_online
),

affected as (
    select distinct c.store_key, o.customer_key
    from closed as c
    join {{ ref('fct_orders') }} as o
      on o.store_key = c.store_key
     and o.order_date between c.close_date - 365 and c.close_date
),

before_after as (
    select
        a.store_key,
        a.customer_key,
        sum(o.net_revenue_usd) filter (where o.order_date between c.close_date - 365 and c.close_date) as revenue_before_usd,
        sum(o.net_revenue_usd) filter (where o.order_date > c.close_date and o.order_date <= c.close_date + 365) as revenue_after_usd,
        bool_or(o.order_date > c.close_date and o.order_date <= c.close_date + 365 and o.channel = 'Online') as came_back_online,
        bool_or(o.order_date > c.close_date and o.order_date <= c.close_date + 365 and o.channel = 'Store') as came_back_in_store
    from affected as a
    join closed as c using (store_key)
    join {{ ref('fct_orders') }} as o using (customer_key)
    group by 1, 2
)

select
    c.store_key,
    c.store_name,
    c.country,
    c.close_date,
    count(*)                                                                    as customers_affected,
    count(*) filter (where came_back_online or came_back_in_store)              as customers_retained,
    count(*) filter (where came_back_online and not came_back_in_store)         as moved_online_only,
    count(*) filter (where came_back_in_store)                                  as moved_to_another_store,
    count(*) filter (where not coalesce(came_back_online or came_back_in_store, false)) as customers_lost,
    round(count(*) filter (where came_back_online or came_back_in_store)::numeric / count(*), 4) as retention_rate,
    coalesce(sum(revenue_before_usd), 0)                                        as revenue_12m_before_usd,
    coalesce(sum(revenue_after_usd), 0)                                         as revenue_12m_after_usd,
    '{{ var("analysis_date") }}'::date >= c.close_date + 365                    as has_full_12m_after
from before_after as b
join closed as c using (store_key)
group by 1, 2, 3, 4
