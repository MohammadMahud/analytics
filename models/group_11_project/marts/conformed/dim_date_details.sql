-- Conformed date dimension shared by fact_inspections and fact_311_service_requests
-- Grain: one row per calendar day that appears in either source
-- Dates used: inspected_date (inspections), created_date and closed_date (311)
-- All three are TIMESTAMP in staging, so CAST to DATE drops the time of day

WITH stg_inspections AS (
    SELECT * FROM {{ ref('stg_primary_data_open_restaurant_inspections') }}
),

stg_311 AS (
    SELECT * FROM {{ ref('stg_source_service_requests_project') }}
),

all_dates AS (
    SELECT CAST(inspected_date AS DATE) AS full_date
    FROM stg_inspections
    WHERE inspected_date IS NOT NULL

    UNION DISTINCT

    SELECT CAST(created_date AS DATE) AS full_date
    FROM stg_311
    WHERE created_date IS NOT NULL

    UNION DISTINCT

    SELECT CAST(closed_date AS DATE) AS full_date
    FROM stg_311
    WHERE closed_date IS NOT NULL
),

date_parts AS (
    SELECT
        full_date,
        EXTRACT(YEAR FROM full_date) AS y,
        EXTRACT(MONTH FROM full_date) AS m,
        EXTRACT(DAY FROM full_date) AS d,
        EXTRACT(DAYOFWEEK FROM full_date) AS dow   -- 1 = Sunday, 2 = Monday, 5 = Thursday, 7 = Saturday
    FROM all_dates
),

date_dimension AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['full_date']) }} AS date_id,
        full_date,
        FORMAT_DATE('%A', full_date) AS day_of_week,
        dow IN (1, 7) AS weekend,
        -- US federal holidays on their calendar date (observed-day shifts not included)
        (
               (m = 1  AND d = 1)                                   -- New Year's Day
            OR (m = 1  AND dow = 2 AND d BETWEEN 15 AND 21)         -- MLK Day: 3rd Monday of January
            OR (m = 2  AND dow = 2 AND d BETWEEN 15 AND 21)         -- Presidents' Day: 3rd Monday of February
            OR (m = 5  AND dow = 2 AND d >= 25)                     -- Memorial Day: last Monday of May
            OR (m = 6  AND d = 19 AND y >= 2021)                    -- Juneteenth (federal since 2021)
            OR (m = 7  AND d = 4)                                   -- Independence Day
            OR (m = 9  AND dow = 2 AND d <= 7)                      -- Labor Day: 1st Monday of September
            OR (m = 10 AND dow = 2 AND d BETWEEN 8 AND 14)          -- Columbus Day: 2nd Monday of October
            OR (m = 11 AND d = 11)                                  -- Veterans Day
            OR (m = 11 AND dow = 5 AND d BETWEEN 22 AND 28)         -- Thanksgiving: 4th Thursday of November
            OR (m = 12 AND d = 25)                                  -- Christmas Day
        ) AS holiday,
        y AS date_year,
        FORMAT_DATE('%B', full_date) AS date_month
    FROM date_parts
),

-- Facts with a missing date point to '-1' so they are not dropped by an inner join
null_placeholder AS (
    SELECT
        '-1' AS date_id,
        CAST(NULL AS DATE) AS full_date,
        CAST(NULL AS STRING) AS day_of_week,
        CAST(NULL AS BOOLEAN) AS weekend,
        CAST(NULL AS BOOLEAN) AS holiday,
        CAST(NULL AS INT64) AS date_year,
        CAST(NULL AS STRING) AS date_month
)

SELECT * FROM date_dimension
UNION ALL
SELECT * FROM null_placeholder