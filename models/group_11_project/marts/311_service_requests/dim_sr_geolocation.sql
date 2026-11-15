-- Service request geolocation dimension for the 311 outdoor dining requests
-- Grain: one row per distinct (x, y, cross street 1, intersection street 1)
--

--
-- fact_311_service_requests must build geo_id from the SAME cleaned x and y,
-- with the same four expressions in the same order, and COALESCE a missing
-- location to '-1'.
--
-- Column names below assume the 311 staging model passes through
-- x_coordinate_state_plane, y_coordinate_state_plane, location, cross_street_1
-- and intersection_street_1. Change them if your table uses other names.

WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_source_service_requests_project') }}
),

parsed AS (
    SELECT
        SAFE_CAST(REPLACE(CAST(x_coordinate_state_plane AS STRING), ',', '') AS FLOAT64) AS x_coordinate,
        SAFE_CAST(REPLACE(CAST(y_coordinate_state_plane AS STRING), ',', '') AS FLOAT64) AS y_coordinate,
        CAST(location AS STRING) AS location_text,
        NULLIF(TRIM(cross_street_1), '') AS cross_street_1,
        NULLIF(TRIM(intersection_street_1), '') AS intersection_street_1
    FROM stg_311
),

-- One row per distinct geolocation. Requests with no geolocation info at all
-- are left out here; the placeholder row below stands in for them.
distinct_geolocations AS (
    SELECT *
    FROM parsed
    WHERE x_coordinate IS NOT NULL
       OR y_coordinate IS NOT NULL
       OR cross_street_1 IS NOT NULL
       OR intersection_street_1 IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY x_coordinate, y_coordinate, UPPER(cross_street_1), UPPER(intersection_street_1)
    ) = 1
),

dim_sr_geo AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'x_coordinate', 'y_coordinate', 'UPPER(cross_street_1)', 'UPPER(intersection_street_1)'
        ]) }} AS sr_geo_id,
        x_coordinate,
        y_coordinate,
        SAFE.ST_GEOGFROMTEXT(location_text) AS location,
        cross_street_1,
        intersection_street_1
    FROM distinct_geolocations
),

-- Null placeholder row: facts with no geolocation point here
null_placeholder AS (
    SELECT
        '-1' AS sr_geo_id,
        CAST(NULL AS FLOAT64) AS x_coordinate,
        CAST(NULL AS FLOAT64) AS y_coordinate,
        CAST(NULL AS GEOGRAPHY) AS location,
        CAST(NULL AS STRING) AS cross_street_1,
        CAST(NULL AS STRING) AS intersection_street_1
)

SELECT * FROM dim_sr_geo
UNION ALL
SELECT * FROM null_placeholder