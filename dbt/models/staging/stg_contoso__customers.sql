-- Customers without personal details: names, street addresses, postcodes, coordinates, employer
-- and vehicle are dropped here and never reach the marts. Only birth year is kept from the birthday.

select
    customer_key::bigint                    as customer_key,
    continent,
    country                                 as country_code,
    country_full                            as country,
    state_full                              as state,
    nullif(gender, '')                      as gender,
    extract(year from birthday::date)::int  as birth_year
from {{ source('raw', 'customer') }}
