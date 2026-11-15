-- Clean and standardize nyc open restaurent inspections
-- One row per inspection

WITH source AS (
   SELECT * FROM {{ source('raw_project', 'primary_data_open_restaurant_inspections') }}
), -- Easier to refer to the dbt reference to a long name table this way

cleaned AS (
   SELECT
       -- Get all columns from source, except ones we're transforming below
       -- To do cleaning on them or explicitly cast them as types just in case
       * EXCEPT (
           restaurantinspectionid,
           businessaddress,
           latitude,
           longitude,
           borough,
           inspectedon,
           postcode
       ),

       -- Identifiers
       CAST(restaurantinspectionid AS STRING) AS inspection_id,

       -- Date/Time
       CAST(inspectedon AS TIMESTAMP) AS inspected_date,


       -- Location - clean postcode code, handling several common postcode code data problems
       CASE
           WHEN UPPER(TRIM(CAST(postcode AS STRING))) IN ('N/A', 'NA') THEN NULL
           WHEN UPPER(TRIM(CAST(postcode AS STRING))) = 'ANONYMOUS' THEN 'Anonymous'
           WHEN LENGTH(CAST(postcode AS STRING)) = 5 THEN CAST(postcode AS STRING)
           WHEN LENGTH(CAST(postcode AS STRING)) = 9 THEN CAST(postcode AS STRING)
           WHEN LENGTH(CAST(postcode AS STRING)) = 10
               AND REGEXP_CONTAINS(CAST(postcode AS STRING), r'^\d{5}-\d{4}')
           THEN CAST(postcode AS STRING)
           ELSE NULL
       END AS zip,

       -- Location - standardized borough, just in case
       CASE
           WHEN UPPER(TRIM(borough)) IN ('MANHATTAN', 'Riverdale','NEW YORK COUNTY') THEN 'Manhattan'
           WHEN UPPER(TRIM(borough)) IN ('BRONX', 'THE BRONX') THEN 'Bronx'
           WHEN UPPER(TRIM(borough)) IN ('BROOKLYN', 'KINGS COUNTY') THEN 'Brooklyn'
           WHEN UPPER(TRIM(borough)) IN ('QUEENS', 'QUEEN', 'Flushing','QUEENS COUNTY') THEN 'Queens'
           WHEN UPPER(TRIM(borough)) IN ('STATEN ISLAND', 'RICHMOND COUNTY') THEN 'Staten Island'
           ELSE 'UNKNOWN or CITYWIDE'
       END AS borough,

       CAST(businessaddress AS STRING) AS restaurant_address,
       CAST(latitude AS DECIMAL) AS latitude,
       CAST(longitude AS DECIMAL) AS longitude,



       -- Metadata
       CURRENT_TIMESTAMP() AS _stg_loaded_at

   FROM source

   -- Filters
   -- WHERE inspectedon >= DATE_SUB(CURRENT_DATE(), INTERVAL 5 YEAR)
   WHERE CAST(inspectedon AS TIMESTAMP) >= TIMESTAMP(DATE_SUB(CURRENT_DATE(), INTERVAL 5 YEAR))
   

   -- Deduplicate
   QUALIFY ROW_NUMBER() OVER (PARTITION BY restaurantinspectionid ORDER BY inspectedon DESC) = 1
)

SELECT * FROM cleaned
-- All should be part of this table after running: stg_primary_data_open_restaurant_inspections.sql