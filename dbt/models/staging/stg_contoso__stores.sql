select
    store_key::int                              as store_key,
    store_code::int                             as store_code,
    description                                 as store_name,
    country_code,
    country_name                                as country,
    state,
    store_key::int = 999999                     as is_online,         -- the one online store
    open_date::date                             as open_date,
    nullif(close_date, '')::date                as close_date,
    coalesce(nullif(status, ''), 'Open')        as status,
    nullif(square_meters, '')::int              as square_meters
from {{ source('raw', 'store') }}
