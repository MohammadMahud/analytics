-- Conformed location dimension shared by fact_inspections and fact_311_service_requests
-- Grain: one row per distinct borough + 5-digit postcode found in either source
--
-- Both staging models output `zip`, and the 311 one keeps ZIP+4 values ('10001-1234',
-- '100011234') and 'Anonymous'. REGEXP_EXTRACT keeps the first 5 digits and returns NULL
-- for anything else, so '10001' and '10001-1234' land on the same row.
--
-- Both fact tables must build their location key with the SAME two expressions in the
-- SAME order, and COALESCE a missing location to '-1':
--   dbt_utils.generate_surrogate_key(['borough', "REGEXP_EXTRACT(zip, r'^[0-9]{5}')"])
-- (Wrap it in double curly braces in the fact file. It is left unwrapped here because
-- dbt runs Jinja inside SQL comments too, and the expanded macro would break this comment.)

WITH stg_inspections AS (
    SELECT * FROM {{ ref('stg_primary_data_open_restaurant_inspections') }}
),

stg_311 AS (
    SELECT * FROM {{ ref('stg_source_service_requests_project') }}
),

all_locations AS (
    SELECT DISTINCT
        borough,
        REGEXP_EXTRACT(zip, r'^[0-9]{5}') AS postcode
    FROM stg_inspections

    UNION DISTINCT

    SELECT DISTINCT
        borough,
        REGEXP_EXTRACT(zip, r'^[0-9]{5}') AS postcode
    FROM stg_311
),

location_dimension AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['borough', 'postcode']) }} AS location_id,
        borough,
        postcode
    FROM all_locations
),

-- Facts with a missing location point to '-1' so they are not dropped by an inner join
null_placeholder AS (
    SELECT
        '-1' AS location_id,
        CAST(NULL AS STRING) AS borough,
        CAST(NULL AS STRING) AS postcode
)

SELECT * FROM location_dimension
UNION ALL
SELECT * FROM null_placeholder