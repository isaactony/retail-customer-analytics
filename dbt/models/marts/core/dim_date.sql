select
    date::date                          as date_day,
    year::int                           as year,
    quarter                             as quarter,
    year_quarter,
    (date_trunc('month', date::date))::date as month_start,
    month,
    month_number::int                   as month_number,
    dayof_week                          as day_name,
    dayof_week_number::int              as iso_day_of_week,
    working_day::boolean                as is_working_day
from {{ source('raw', 'date') }}
