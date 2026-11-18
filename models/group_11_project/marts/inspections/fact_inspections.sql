-- Fact table: Outdoor dining restaurant inspections
-- Grain: one row per inspection (inspection_id, controlled in staging model)

-- Make sure you have access to staging and its grain
WITH stg_inspections AS (
    SELECT * FROM {{ ref('stg_primary_data_open_restaurant_inspections') }}
),

-- All the dimensions in their own CTEs for easy reference
dim_details AS (
    SELECT * FROM {{ ref('dim_business_details') }}
),

dim_location AS (
    SELECT * FROM {{ ref('dim_location_details') }}
),

dim_date AS (
    SELECT * FROM {{ ref('dim_date_details') }}
),

-- Build intial CTE for fact table
fact_inspection_data AS (

    SELECT
        -- Fact's own surrogate key, from the grain (this is deduped in staging)
        {{ dbt_utils.generate_surrogate_key(['s.inspection_id']) }} AS restaurant_inspection_id,
        -- Degenerate dimension (business identifier)
        s.inspection_id,

        -- Open requests legitimately have no closed date -> unknown member
        CASE WHEN s.inspected_date IS NULL THEN '-1' ELSE d.date_id END AS inspected_on,
        -- Always will have a location key
        l.location_id,
        -- Always will have a business id
        bd.business_id,
 
        -- plus date from the other fields
        s.skippedreason,
        s.isroadwaycompliant,
        s.longitude,
        s.latitude,
        s.bbl
    FROM stg_inspections s

    -- Left joins because you want all the rows from staging in the fact rep'd, with key information from dimensions
    -- JOIN ON the items that make up the surrogate key in the dimension
    LEFT JOIN dim_date d
        ON CAST(s.inspected_date AS DATE) = d.full_date

    -- IS NOT DISTINCT FROM so a NULL zip / borough matches the dim row
    -- Could leave out the NULL exception and make these =s
    LEFT JOIN dim_location l
        ON  s.borough     IS NOT DISTINCT FROM l.borough
        AND s.zip         IS NOT DISTINCT FROM l.postcode
    
    -- IS NOT DISTINCT FROM so a NULL restaurantname / legabusinessname/restaurant_address matches the dim row
    LEFT JOIN dim_details bd
        ON  s.restaurantname IS NOT DISTINCT FROM bd.restaurantname
        AND s.legalbusinessname IS NOT DISTINCT FROM bd.legalbusinessname
        AND s.restaurant_address IS NOT DISTINCT FROM bd.businessaddress
)

SELECT * FROM fact_inspection_data