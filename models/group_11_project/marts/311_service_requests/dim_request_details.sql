WITH stg_311 AS (
    SELECT * FROM {{ ref('stg_source_service_requests_project') }}
),

distinct_requests AS (

    SELECT DISTINCT
        complaint_type AS problem,
        descriptor AS problem_detail,
        resolution_description,
        status
    FROM stg_311
    WHERE complaint_type IS NOT NULL

),

dim_request_details AS (

    SELECT
        {{ dbt_utils.generate_surrogate_key([
            'problem', 'problem_detail',
            'resolution_description', 'status'
        ]) }} AS request_type_details,

        problem,
        problem_detail,
        resolution_description,
        status

    FROM distinct_requests

)

SELECT * FROM dim_request_details
