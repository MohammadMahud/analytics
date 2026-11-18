-- Fact table: 311 outdoor dining service requests
-- Grain: one row per service request (request_id, controlled in staging model)

WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_source_service_requests_project') }}
),

-- All the dimensions in their own CTEs for easy reference
dim_request AS (
    SELECT * FROM {{ ref('dim_request_details') }}
),

dim_location AS (
    SELECT * FROM {{ ref('dim_location_details') }}
),

dim_date AS (
    SELECT * FROM {{ ref('dim_date_details') }}
),

dim_geo AS (
    SELECT * FROM {{ ref('dim_sr_geolocation') }}
),

-- Build initial CTE for fact table
fact_311_data AS (

    SELECT
    --Primary key: 311 request ID
        s.request_id AS unique_key,
        
        cd.date_id AS created_date,
        CASE WHEN s.closed_date IS NULL THEN '-1' ELSE xd.date_id END AS closed_date,
        l.location_id AS request_location_id,
        r.request_type_details AS request_type,
        g.sr_geo_id AS geo_id,

        -- data from the other fields
        s.status,
        s.agency,
        s.agency_name,
        s.method_of_submission AS open_data_channel_type,
        s.latitude,
        s.longitude

    FROM stg_311 s

    LEFT JOIN dim_date cd
        ON CAST(s.created_date AS DATE) = cd.full_date

    LEFT JOIN dim_date xd
        ON CAST(s.closed_date AS DATE) = xd.full_date

    -- IS NOT DISTINCT FROM so a NULL zip / borough matches the dim row
    LEFT JOIN dim_location l
        ON  s.borough IS NOT DISTINCT FROM l.borough
        AND REGEXP_EXTRACT(s.zip, r'^[0-9]{5}') IS NOT DISTINCT FROM l.postcode

    -- Complaint_type / descriptor are stored as problem / problem_detail in the dim
    LEFT JOIN dim_request r
        ON  s.complaint_type IS NOT DISTINCT FROM r.problem
        AND s.descriptor IS NOT DISTINCT FROM r.problem_detail
        AND s.resolution_description IS NOT DISTINCT FROM r.resolution_description
        AND s.status IS NOT DISTINCT FROM r.status

    -- Same cleaning dim_sr_geolocation applies to x, y and the two street columns
    LEFT JOIN dim_geo g
        ON  SAFE_CAST(REPLACE(CAST(s.x_coordinate_state_plane AS STRING), ',', '') AS FLOAT64)
                IS NOT DISTINCT FROM g.x_coordinate
        AND SAFE_CAST(REPLACE(CAST(s.y_coordinate_state_plane AS STRING), ',', '') AS FLOAT64)
                IS NOT DISTINCT FROM g.y_coordinate
        AND UPPER(NULLIF(TRIM(s.cross_street_1), ''))
                IS NOT DISTINCT FROM UPPER(g.cross_street_1)
        AND UPPER(NULLIF(TRIM(s.intersection_street_1), ''))
                IS NOT DISTINCT FROM UPPER(g.intersection_street_1)
)

SELECT * FROM fact_311_data
