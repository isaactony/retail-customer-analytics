select
    date::date                  as rate_date,
    from_currency,
    to_currency,
    exchange::numeric           as rate
from {{ source('raw', 'currencyexchange') }}
