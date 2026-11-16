-- Service request geolocation dimension for the 311 outdoor dining requests
-- Grain: one row per distinct (x, y, cross street 1, intersection street 1)
--
-- Source quirks (from profiling the CSV):
--   * x/y arrive as text with thousands commas, e.g. '985,776'
--   * the staging model has no location column, so the GEOGRAPHY point is
--     built from latitude and longitude instead
--   * BigQuery cannot PARTITION BY a FLOAT64 column, so we build the surrogate
--     key first and de-duplicate on the key (a STRING)
--
-- fact_311_service_requests must build geo_id from the SAME cleaned x and y,
-- with the same four expressions in the same order, and COALESCE a missing
-- location to '-1'.

WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_source_service_requests_project') }}
),

parsed AS (
    SELECT
        SAFE_CAST(REPLACE(CAST(x_coordinate_state_plane AS STRING), ',', '') AS FLOAT64) AS x_coordinate,
        SAFE_CAST(REPLACE(CAST(y_coordinate_state_plane AS STRING), ',', '') AS FLOAT64) AS y_coordinate,
        SAFE_CAST(latitude AS FLOAT64) AS latitude,
        SAFE_CAST(longitude AS FLOAT64) AS longitude,
        NULLIF(TRIM(cross_street_1), '') AS cross_street_1,
        NULLIF(TRIM(intersection_street_1), '') AS intersection_street_1
    FROM stg_311
),

keyed AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'x_coordinate', 'y_coordinate', 'UPPER(cross_street_1)', 'UPPER(intersection_street_1)'
        ]) }} AS sr_geo_id,
        *
    FROM parsed
),

-- One row per distinct geolocation. Requests with no geolocation info at all
-- are left out here; the placeholder row below stands in for them.
distinct_geolocations AS (
    SELECT *
    FROM keyed
    WHERE x_coordinate IS NOT NULL
       OR y_coordinate IS NOT NULL
       OR cross_street_1 IS NOT NULL
       OR intersection_street_1 IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY sr_geo_id) = 1
),

dim_sr_geo AS (
    SELECT
        sr_geo_id,
        x_coordinate,
        y_coordinate,
        SAFE.ST_GEOGPOINT(longitude, latitude) AS location,
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