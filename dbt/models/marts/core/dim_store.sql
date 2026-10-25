with activity as (
    select store_key, min(order_date) as first_order_date, max(order_date) as last_order_date
    from {{ ref('stg_contoso__orders') }}
    group by 1
)

select
    s.*,
    a.first_order_date,
    a.last_order_date,
    s.close_date is not null and s.close_date >= date '2016-05-18'  as closed_during_extract
from {{ ref('stg_contoso__stores') }} as s
left join activity as a using (store_key)
