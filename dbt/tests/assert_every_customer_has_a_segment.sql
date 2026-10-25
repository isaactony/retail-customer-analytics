-- The RFM mart inner-joins the segment seed; a score combination missing from the seed would
-- silently drop customers. Both counts must match.

select (select count(*) from {{ ref('dim_customer') }}) as customers,
       (select count(*) from {{ ref('mart_customer_rfm') }}) as segmented
where (select count(*) from {{ ref('dim_customer') }}) <> (select count(*) from {{ ref('mart_customer_rfm') }})
