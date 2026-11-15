-- Business dimension for the Open Restaurants inspections
-- Grain: one row per business (restaurant name + legal business name + address)
--
-- The inspections data has no business ID, so the surrogate key is built from
-- the three identifying columns, upper-cased so 'Joe''s Pizza' and 'JOE''S PIZZA'
-- count as the same business. seatingchoice can change between inspections
--
-- fact_inspections must build business_id with the SAME three expressions in
-- the SAME order, and COALESCE a missing business to '-1'.

WITH stg_inspections AS (
    SELECT * FROM {{ ref('stg_primary_data_open_restaurant_inspections') }}
),

-- One row per business: keep the most recent inspection's values
distinct_businesses AS (
    SELECT
        restaurantname,
        legalbusinessname,
        restaurant_address AS businessaddress,
        seatingchoice,
        inspected_date
    FROM stg_inspections
    WHERE restaurantname IS NOT NULL
       OR legalbusinessname IS NOT NULL
       OR restaurant_address IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY UPPER(restaurantname), UPPER(legalbusinessname), UPPER(restaurant_address)
        ORDER BY inspected_date DESC
    ) = 1
),

dim_business AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'UPPER(restaurantname)', 'UPPER(legalbusinessname)', 'UPPER(businessaddress)'
        ]) }} AS business_id,
        businessaddress,
        legalbusinessname,
        restaurantname,
        seatingchoice
    FROM distinct_businesses
),

-- Null placeholder row: facts with no identifiable business point here
null_placeholder AS (
    SELECT
        '-1' AS business_id,
        CAST(NULL AS STRING) AS businessaddress,
        CAST(NULL AS STRING) AS legalbusinessname,
        CAST(NULL AS STRING) AS restaurantname,
        CAST(NULL AS STRING) AS seatingchoice
)

SELECT * FROM dim_business
UNION ALL
SELECT * FROM null_placeholder