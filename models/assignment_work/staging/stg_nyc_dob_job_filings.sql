-- =====================================================================
-- Staging model: stg_nyc_dob_job_filings
-- Source: NYC Open Data - DOB NOW: Build - Job Application Filings
-- Grain: one row per job filing (job_filing_id), most recent version kept
--
-- What this model does:
--   1. Casts columns to explicit types (SAFE_CAST so one bad value
--      becomes NULL instead of crashing the whole run)
--   2. Cleans text, zip codes and borough names
--   3. Removes duplicate filings
--   4. Adds helper columns derived from the job filing number
-- =====================================================================

WITH source AS (
    -- Easier to refer to the dbt reference to a long name table this way
    SELECT * FROM {{ source('raw', 'source_DOB_homework') }}
),

-- ---------------------------------------------------------------------
-- STEP 1: clean + cast + deduplicate
-- ---------------------------------------------------------------------
cleaned AS (
    SELECT
        -- Pass through every column we do NOT touch below.
        -- Anything we re-create in this SELECT must be listed here,
        -- otherwise it would appear twice.
        -- Careful: BigQuery does NOT allow a comma after the last item.
        * EXCEPT (
            job_filing_number,
            filing_status,
            filing_date,
            current_status_date,
            approved_date,
            first_permit_date,         -- needed by dim_date
            signoff_date,              -- needed by dim_date
            house_no,
            street_name,
            work_on_floor,
            review_building_code,
            applicant_business_name,   -- not in data dictionary: delete if missing from your table
            job_description,           -- not in data dictionary: delete if missing from your table
            earth_work_work_type_,     -- not in data dictionary: delete if missing from your table
            zip,
            postcode,                  -- not in data dictionary: delete if missing from your table
            borough,
            latitude,
            longitude
        ),

        -- Identifiers
        CAST(job_filing_number AS STRING) AS job_filing_id,
        TRIM(CAST(filing_status AS STRING)) AS filing_status,

        -- Date/Time (SAFE_CAST: a malformed value becomes NULL, not an error)
        SAFE_CAST(filing_date AS TIMESTAMP) AS filing_date,
        SAFE_CAST(current_status_date AS TIMESTAMP) AS current_status_date,
        SAFE_CAST(approved_date AS TIMESTAMP) AS approved_date,
        SAFE_CAST(first_permit_date AS TIMESTAMP) AS first_permit_date,
        SAFE_CAST(signoff_date AS TIMESTAMP) AS signoff_date,

        -- Building details
        TRIM(CAST(house_no AS STRING)) AS house_no,
        TRIM(CAST(street_name AS STRING)) AS street_name,
        TRIM(CAST(work_on_floor AS STRING)) AS work_on_floor,
        TRIM(CAST(review_building_code AS STRING)) AS review_building_code,

        -- Filing details - clearer column names where it helps
        CAST(applicant_business_name AS STRING) AS business_name,
        CAST(job_description AS STRING) AS job_description,
        CAST(earth_work_work_type_ AS STRING) AS earth_work_type,

        -- Location - owner's zip code.
        -- Valid formats: 12345, 123456789, 12345-6789. Everything else -> NULL
        CASE
            WHEN UPPER(TRIM(CAST(zip AS STRING))) IN ('N/A', 'NA') THEN NULL
            WHEN REGEXP_CONTAINS(TRIM(CAST(zip AS STRING)), r'^\d{5}(-?\d{4})?$')
                THEN TRIM(CAST(zip AS STRING))
            ELSE NULL
        END AS zip,

        -- Location - postcode, same cleaning rules
        CASE
            WHEN UPPER(TRIM(CAST(postcode AS STRING))) IN ('N/A', 'NA') THEN NULL
            WHEN REGEXP_CONTAINS(TRIM(CAST(postcode AS STRING)), r'^\d{5}(-?\d{4})?$')
                THEN TRIM(CAST(postcode AS STRING))
            ELSE NULL
        END AS postcode,

        -- Location - standardized borough. Unrecognized values stay NULL here;
        -- the next step tries to recover them from the job filing number.
        CASE
            WHEN UPPER(TRIM(borough)) IN ('MANHATTAN', 'NEW YORK COUNTY') THEN 'Manhattan'
            WHEN UPPER(TRIM(borough)) IN ('BRONX', 'THE BRONX') THEN 'Bronx'
            WHEN UPPER(TRIM(borough)) IN ('BROOKLYN', 'KINGS COUNTY') THEN 'Brooklyn'
            WHEN UPPER(TRIM(borough)) IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY') THEN 'Queens'
            WHEN UPPER(TRIM(borough)) IN ('STATEN ISLAND', 'RICHMOND COUNTY') THEN 'Staten Island'
            ELSE NULL
        END AS borough,

        -- Geospatial (FLOAT64 matches the FLOAT type in the BigQuery schema)
        SAFE_CAST(latitude AS FLOAT64) AS latitude,
        SAFE_CAST(longitude AS FLOAT64) AS longitude

        -- OPTIONAL: more columns from the data dictionary. Before uncommenting,
        -- confirm the exact names with INFORMATION_SCHEMA.COLUMNS, and add each
        -- one to the EXCEPT list above.
        -- , SAFE_CAST(initial_cost AS FLOAT64) AS initial_cost
        -- , SAFE_CAST(total_construction_floor_area AS FLOAT64) AS total_construction_floor_area
        -- , SAFE_CAST(existing_stories AS INT64) AS existing_stories
        -- , SAFE_CAST(proposed_no_of_stories AS INT64) AS proposed_stories

    FROM source

    -- Filters: a filing without an ID is unusable
    WHERE job_filing_number IS NOT NULL

    -- Deduplicate: keep the most recently modified row per job filing.
    -- (QUALIFY needs a true/false condition, hence "= 1")
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY job_filing_number
        ORDER BY current_status_date DESC
    ) = 1
),

-- ---------------------------------------------------------------------
-- STEP 2: derived columns
-- (A separate step, because BigQuery can't reuse an alias created
--  in the same SELECT.)
-- ---------------------------------------------------------------------
enriched AS (
    SELECT
        * EXCEPT (borough),

        -- Borough: use the cleaned value; if missing, fall back to the first letter
        -- of the job filing number (B=Brooklyn, M=Manhattan, Q=Queens,
        -- S=Staten Island, X=Bronx, per the data dictionary).
        COALESCE(
            borough,
            CASE UPPER(SUBSTR(job_filing_id, 1, 1))
                WHEN 'M' THEN 'Manhattan'
                WHEN 'X' THEN 'Bronx'
                WHEN 'B' THEN 'Brooklyn'
                WHEN 'Q' THEN 'Queens'
                WHEN 'S' THEN 'Staten Island'
            END,
            'UNKNOWN'
        ) AS borough,

        -- Filing type: the letter before the number at the end of the ID
        -- (e.g. M00012345-I1). I = Initial, P = Post Approval Amendment, S = Subsequent
        CASE REGEXP_EXTRACT(job_filing_id, r'-([A-Za-z])\d+$')
            WHEN 'I' THEN 'Initial'
            WHEN 'P' THEN 'Post Approval Amendment'
            WHEN 'S' THEN 'Subsequent'
            ELSE 'Unknown'
        END AS filing_type,

        -- Sequence number: I1 = 1, S2 = 2, and so on
        SAFE_CAST(REGEXP_EXTRACT(job_filing_id, r'-[A-Za-z](\d+)$') AS INT64) AS filing_sequence,

        -- One readable address column
        NULLIF(TRIM(CONCAT(COALESCE(house_no, ''), ' ', COALESCE(street_name, ''))), '') AS full_address,

        -- How long approval took (NULL if never approved)
        DATE_DIFF(DATE(approved_date), DATE(filing_date), DAY) AS days_to_approval,

        -- Metadata
        CURRENT_TIMESTAMP() AS _stg_loaded_at

    FROM cleaned
)

SELECT * FROM enriched
-- All should be part of this table after running: stg_nyc_dob_job_filings