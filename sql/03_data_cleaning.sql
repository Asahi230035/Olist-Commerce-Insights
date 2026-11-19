USE olist_analysis;

-- ==========================================
-- 03 数据清洗与标准化
-- 1. 订单时间质量检查与标准化
-- ==========================================

CREATE OR REPLACE VIEW v_orders_clean AS

SELECT
    o.*,

    -- 1. 已送达订单缺少签收时间
    CASE
        WHEN order_status = 'delivered'
             AND order_delivered_customer_date IS NULL
        THEN 1 ELSE 0
    END AS flag_missing_delivery,

    -- 2. 已取消订单仍有签收时间
    CASE
        WHEN order_status = 'canceled'
             AND order_delivered_customer_date IS NOT NULL
        THEN 1 ELSE 0
    END AS flag_canceled_delivered,

    -- 3. 承运商交接早于购买
    CASE
        WHEN order_delivered_carrier_date
             < order_purchase_timestamp
        THEN 1 ELSE 0
    END AS flag_carrier_before_purchase,

    -- 4. 签收早于承运商交接
    CASE
        WHEN order_delivered_customer_date
             < order_delivered_carrier_date
        THEN 1 ELSE 0
    END AS flag_delivery_before_carrier,

    -- 5. 购买至签收时长是否有效
    CASE
        WHEN order_status = 'delivered'
             AND order_purchase_timestamp IS NOT NULL
             AND order_delivered_customer_date IS NOT NULL
             AND order_delivered_customer_date
                 >= order_purchase_timestamp
        THEN 1 ELSE 0
    END AS is_valid_delivery,

    -- 6. 承运商运输时长是否有效
    CASE
        WHEN order_status = 'delivered'
             AND order_delivered_carrier_date IS NOT NULL
             AND order_delivered_customer_date IS NOT NULL
             AND order_delivered_carrier_date
                 >= order_purchase_timestamp
             AND order_delivered_customer_date
                 >= order_delivered_carrier_date
        THEN 1 ELSE 0
    END AS is_valid_transit,

    -- 7. 实际配送总时长（天）
    CASE
        WHEN order_status = 'delivered'
             AND order_delivered_customer_date IS NOT NULL
             AND order_delivered_customer_date
                 >= order_purchase_timestamp
        THEN ROUND(
            TIMESTAMPDIFF(
                SECOND,
                order_purchase_timestamp,
                order_delivered_customer_date
            ) / 86400.0,
            2
        )
        ELSE NULL
    END AS delivery_days,

    -- 8. 是否延迟送达
    CASE
        WHEN order_status = 'delivered'
             AND order_delivered_customer_date IS NOT NULL
             AND order_delivered_customer_date
                 >= order_purchase_timestamp
             AND order_estimated_delivery_date IS NOT NULL
        THEN
            CASE
                WHEN DATE(order_delivered_customer_date)
                     > DATE(order_estimated_delivery_date)
                THEN 1 ELSE 0
            END
        ELSE NULL
    END AS is_late_delivery

FROM orders o;
-- ==========================================
-- 2. 商品数据清洗与类别标准化
-- ==========================================

CREATE OR REPLACE VIEW v_products_clean AS

SELECT
    p.*,

    -- 1. 标准商品类别
    CASE
        WHEN p.product_category_name IS NULL
            THEN 'unknown'

        WHEN t.product_category_name_english IS NULL
            THEN p.product_category_name

        ELSE t.product_category_name_english
    END AS category_label,

    -- 2. 商品类别质量状态
    CASE
        WHEN p.product_category_name IS NULL
            THEN 'missing_category'

        WHEN t.product_category_name IS NULL
            THEN 'missing_translation'

        ELSE 'valid'
    END AS category_status,

    -- 3. 商品重量和尺寸是否完整有效
    CASE
        WHEN p.product_weight_g > 0
         AND p.product_length_cm > 0
         AND p.product_height_cm > 0
         AND p.product_width_cm > 0
        THEN 1
        ELSE 0
    END AS is_valid_dimension

FROM products p

LEFT JOIN category_translation t
    ON p.product_category_name =
       t.product_category_name;
-- ==========================================
-- 3. 评价数据清洗与标准化
-- ==========================================

CREATE OR REPLACE VIEW v_reviews_clean AS

SELECT
    r.*,

    -- 1. 评分是否有效
    CASE
        WHEN review_score BETWEEN 1 AND 5
        THEN 1 ELSE 0
    END AS is_valid_score,

    -- 2. 是否填写评价标题
    CASE
        WHEN NULLIF(TRIM(review_comment_title), '') IS NOT NULL
        THEN 1 ELSE 0
    END AS has_review_title,

    -- 3. 是否填写评价内容
    CASE
        WHEN NULLIF(TRIM(review_comment_message), '') IS NOT NULL
        THEN 1 ELSE 0
    END AS has_review_message,

    -- 4. 同一评价 ID 对应的记录数
    COUNT(*) OVER (
        PARTITION BY review_id
    ) AS review_id_count,

    -- 5. 同一订单对应的评价记录数
    COUNT(*) OVER (
        PARTITION BY order_id
    ) AS order_review_count,

    -- 6. 评价回复时间是否早于创建时间
    CASE
        WHEN review_answer_timestamp < review_creation_date
        THEN 1 ELSE 0
    END AS flag_invalid_answer_time

FROM order_reviews r;
-- ==========================================
-- 4. 地理位置数据标准化
-- ==========================================

-- 1. 地理位置基础检查

SELECT
    COUNT(*) AS total_records,

    COUNT(DISTINCT geolocation_zip_code_prefix)
        AS unique_zip_codes,

    COUNT(*) - COUNT(DISTINCT geolocation_zip_code_prefix)
        AS extra_zip_records,

    COUNT(DISTINCT geolocation_state)
        AS unique_states

FROM geolocation;
-- 2. 经纬度与邮编格式检查

SELECT
    COUNT(*) AS total_records,

    SUM(
        geolocation_lat NOT BETWEEN -90 AND 90
    ) AS invalid_latitude,

    SUM(
        geolocation_lng NOT BETWEEN -180 AND 180
    ) AS invalid_longitude,

    SUM(
        geolocation_zip_code_prefix IS NULL
        OR NOT REGEXP_LIKE(
            geolocation_zip_code_prefix,
            '^[0-9]{5}$'
        )
    ) AS invalid_zip_code

FROM geolocation;
-- 3. 邮编与城市、州的一致性检查

WITH zip_profile AS (
    SELECT
        geolocation_zip_code_prefix AS zip_code,

        COUNT(*) AS record_count,

        COUNT(DISTINCT geolocation_city)
            AS city_count,

        COUNT(DISTINCT geolocation_state)
            AS state_count

    FROM geolocation

    GROUP BY geolocation_zip_code_prefix
)

SELECT
    COUNT(*) AS total_zip_codes,

    SUM(city_count > 1)
        AS multi_city_zip_codes,

    SUM(state_count > 1)
        AS multi_state_zip_codes,

    MAX(record_count)
        AS max_records_per_zip

FROM zip_profile
-- ==========================================
-- 4. 地理位置数据清洗与标准化
-- ==========================================

CREATE OR REPLACE VIEW v_geolocation_clean AS

WITH distinct_locations AS (

    -- 1. 去除完全重复的位置记录
    -- 同时统一城市名称的大小写与首尾空格

    SELECT DISTINCT
        geolocation_zip_code_prefix AS zip_code,
        LOWER(TRIM(geolocation_city)) AS city,
        UPPER(TRIM(geolocation_state)) AS state,
        geolocation_lat AS latitude,
        geolocation_lng AS longitude

    FROM geolocation
),

location_frequency AS (

    -- 2. 按邮编、城市、州统计位置记录
    -- 使用去重后的坐标，避免完全重复记录影响权重

    SELECT
        zip_code,
        city,
        state,

        COUNT(*) AS location_count,

        AVG(latitude) AS latitude,
        AVG(longitude) AS longitude

    FROM distinct_locations

    GROUP BY
        zip_code,
        city,
        state
),

ranked_locations AS (

    -- 3. 对每个邮编的候选城市和州进行排序
    -- 优先选择出现频率最高的组合

    SELECT
        *,

        ROW_NUMBER() OVER (
            PARTITION BY zip_code
            ORDER BY
                location_count DESC,
                state ASC,
                city ASC
        ) AS rn

    FROM location_frequency
),

zip_profile AS (

    -- 4. 统计原始邮编记录数量及冲突情况

    SELECT
        geolocation_zip_code_prefix AS zip_code,

        COUNT(*) AS source_record_count,

        COUNT(DISTINCT geolocation_city)
            AS city_count,

        COUNT(DISTINCT geolocation_state)
            AS state_count

    FROM geolocation

    GROUP BY geolocation_zip_code_prefix
)

-- 5. 构建每个邮编一行的标准化结果

SELECT
    r.zip_code,
    r.city,
    r.state,

    ROUND(r.latitude, 6) AS latitude,
    ROUND(r.longitude, 6) AS longitude,

    p.source_record_count,

    p.city_count,
    p.state_count,

    CASE
        WHEN p.state_count > 1
            THEN 'multi_state'

        WHEN p.city_count > 1
            THEN 'multi_city'

        ELSE 'consistent'
    END AS location_quality_flag

FROM ranked_locations r

JOIN zip_profile p
    ON r.zip_code = p.zip_code

WHERE r.rn = 1;
SELECT
    COUNT(*) AS total_zip_codes,

    COUNT(DISTINCT zip_code) AS unique_zip_codes,

    SUM(city_count > 1) AS multi_city_zip_codes,

    SUM(state_count > 1) AS multi_state_zip_codes,

    SUM(source_record_count) AS original_records

FROM v_geolocation_clean;
SELECT
    zip_code,
    COUNT(*) AS record_count

FROM v_geolocation_clean

GROUP BY zip_code

HAVING COUNT(*) > 1;