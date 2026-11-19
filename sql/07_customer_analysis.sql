
USE olist_analysis;
-- 5.1 用户购买行为分析
-- 5.1.1 用户规模与复购率
WITH valid_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        SUM(oi.price) AS order_gmv
    FROM orders o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'
    GROUP BY
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
),

customer_summary AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS order_count,
        SUM(order_gmv) AS total_gmv
    FROM valid_orders
    GROUP BY customer_unique_id
)

SELECT
    COUNT(*) AS total_customers,
    SUM(order_count) AS total_orders,
    SUM(order_count >= 2) AS repeat_customers,
    ROUND(
        100.0 * SUM(order_count >= 2) / COUNT(*),
        2
    ) AS repeat_customer_rate_pct,
    ROUND(SUM(total_gmv), 2) AS total_gmv,
    ROUND(AVG(total_gmv), 2) AS avg_customer_value
FROM customer_summary;

-- 5.1.2 用户购买频次分布
WITH valid_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        SUM(oi.price) AS order_gmv
    FROM orders o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'
    GROUP BY c.customer_unique_id, o.order_id
),

customer_summary AS (
    SELECT
        customer_unique_id,
        COUNT(*) AS order_count,
        SUM(order_gmv) AS total_gmv
    FROM valid_orders
    GROUP BY customer_unique_id
),

frequency_groups AS (
    SELECT
        CASE
            WHEN order_count = 1 THEN 1
            WHEN order_count = 2 THEN 2
            WHEN order_count = 3 THEN 3
            ELSE 4
        END AS frequency_level,
        total_gmv,
        order_count
    FROM customer_summary
),

group_summary AS (
    SELECT
        frequency_level,
        COUNT(*) AS customer_count,
        SUM(order_count) AS total_orders,
        ROUND(SUM(total_gmv), 2) AS total_gmv,
        ROUND(AVG(total_gmv), 2) AS avg_customer_gmv
    FROM frequency_groups
    GROUP BY frequency_level
)

SELECT
    CASE frequency_level
        WHEN 1 THEN '1 order'
        WHEN 2 THEN '2 orders'
        WHEN 3 THEN '3 orders'
        ELSE '4+ orders'
    END AS frequency_group,

    customer_count,
    total_orders,

    ROUND(
        100.0 * customer_count
        / SUM(customer_count) OVER (),
        2
    ) AS customer_share_pct,

    total_gmv,

    ROUND(
        100.0 * total_gmv
        / SUM(total_gmv) OVER (),
        2
    ) AS gmv_share_pct,

    avg_customer_gmv

FROM group_summary
ORDER BY frequency_level;
-- 5.2 构建用户级 RFM 分析视图
CREATE OR REPLACE VIEW v_customer_rfm AS

WITH valid_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        SUM(oi.price) AS order_gmv
    FROM orders o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'
    GROUP BY
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp
)

SELECT
    customer_unique_id,

    DATEDIFF(
        '2018-09-01',
        DATE(MAX(order_purchase_timestamp))
    ) AS recency_days,

    COUNT(*) AS frequency,

    ROUND(SUM(order_gmv), 2) AS monetary

FROM valid_orders
GROUP BY customer_unique_id;


SELECT
    COUNT(*) AS total_customers,
    SUM(frequency) AS total_orders,
    ROUND(SUM(monetary), 2) AS total_gmv,

    MIN(recency_days) AS min_recency,
    MAX(recency_days) AS max_recency,

    MIN(frequency) AS min_frequency,
    MAX(frequency) AS max_frequency,

    ROUND(AVG(monetary), 2) AS avg_monetary

FROM v_customer_rfm;

-- 5.3 RFM 数据分布分析
-- R、M 分位数查询
WITH ranked AS (
    SELECT
        recency_days,
        monetary,

        ROW_NUMBER() OVER (
            ORDER BY recency_days
        ) AS r_rank,

        ROW_NUMBER() OVER (
            ORDER BY monetary
        ) AS m_rank,

        COUNT(*) OVER () AS total_count

    FROM v_customer_rfm
)

SELECT
    MAX(CASE WHEN r_rank = CEIL(total_count * 0.25)
        THEN recency_days END) AS r_p25,

    MAX(CASE WHEN r_rank = CEIL(total_count * 0.50)
        THEN recency_days END) AS r_p50,

    MAX(CASE WHEN r_rank = CEIL(total_count * 0.75)
        THEN recency_days END) AS r_p75,

    MAX(CASE WHEN r_rank = CEIL(total_count * 0.90)
        THEN recency_days END) AS r_p90,

    MAX(CASE WHEN m_rank = CEIL(total_count * 0.25)
        THEN monetary END) AS m_p25,

    MAX(CASE WHEN m_rank = CEIL(total_count * 0.50)
        THEN monetary END) AS m_p50,

    MAX(CASE WHEN m_rank = CEIL(total_count * 0.75)
        THEN monetary END) AS m_p75,

    MAX(CASE WHEN m_rank = CEIL(total_count * 0.90)
        THEN monetary END) AS m_p90

FROM ranked;

-- 5.4 RFM 用户评分
-- 5.4.1 构建 RFM 评分视图

CREATE OR REPLACE VIEW v_customer_rfm_scored AS
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,

    -- R：最近购买时间越近，得分越高
    CASE
        WHEN recency_days <= 117 THEN 4
        WHEN recency_days <= 221 THEN 3
        WHEN recency_days <= 348 THEN 2
        ELSE 1
    END AS r_score,

    -- F：按照实际购买频次分为三级
    CASE
        WHEN frequency >= 3 THEN 3
        WHEN frequency = 2 THEN 2
        ELSE 1
    END AS f_score,

    -- M：累计消费金额越高，得分越高
    CASE
        WHEN monetary > 154.17 THEN 4
        WHEN monetary > 89.70 THEN 3
        WHEN monetary > 47.65 THEN 2
        ELSE 1
    END AS m_score

FROM v_customer_rfm;


-- 5.4.2 RFM 评分结果完整性检查

SELECT
    COUNT(*) AS total_customers,
    COUNT(DISTINCT customer_unique_id) AS unique_customers,
    SUM(frequency) AS total_orders,
    ROUND(SUM(monetary), 2) AS total_gmv
FROM v_customer_rfm_scored;


-- 5.4.3 RFM 各维度评分分布

SELECT
    'R' AS score_type,
    r_score AS score,
    COUNT(*) AS customer_count
FROM v_customer_rfm_scored
GROUP BY r_score

UNION ALL

SELECT
    'F' AS score_type,
    f_score AS score,
    COUNT(*) AS customer_count
FROM v_customer_rfm_scored
GROUP BY f_score

UNION ALL

SELECT
    'M' AS score_type,
    m_score AS score,
    COUNT(*) AS customer_count
FROM v_customer_rfm_scored
GROUP BY m_score

ORDER BY score_type, score;

-- 5.5 RFM 用户分层与价值分析
-- 5.5.1 构建 RFM 用户分层视图

CREATE OR REPLACE VIEW v_customer_rfm_segmented AS
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,

    -- 优先识别复购用户，再根据近期购买情况和消费金额细分
    CASE
        WHEN f_score >= 2 AND r_score >= 3 AND m_score = 4
            THEN 'A_近期高消费复购'

        WHEN f_score >= 2 AND r_score >= 3
            THEN 'B_近期其他复购'

        WHEN f_score >= 2
            THEN 'C_非近期复购'

        WHEN f_score = 1 AND r_score >= 3 AND m_score = 4
            THEN 'D_近期高消费单次'

        WHEN f_score = 1 AND r_score >= 3
            THEN 'E_近期其他单次'

        WHEN f_score = 1 AND m_score = 4
            THEN 'F_非近期高消费单次'

        ELSE 'G_非近期其他单次'
    END AS customer_segment

FROM v_customer_rfm_scored;


-- 5.5.2 各用户群体规模及 GMV 贡献分析

WITH segment_summary AS (
    SELECT
        customer_segment,
        COUNT(*) AS customer_count,
        SUM(frequency) AS total_orders,
        ROUND(SUM(monetary), 2) AS total_gmv,
        ROUND(AVG(monetary), 2) AS avg_customer_gmv,
        ROUND(AVG(recency_days), 2) AS avg_recency_days

    FROM v_customer_rfm_segmented
    GROUP BY customer_segment
)

SELECT
    customer_segment,
    customer_count,

    ROUND(
        100.0 * customer_count
        / SUM(customer_count) OVER (),
        2
    ) AS customer_share_pct,

    total_orders,
    total_gmv,

    ROUND(
        100.0 * total_gmv
        / SUM(total_gmv) OVER (),
        2
    ) AS gmv_share_pct,

    avg_customer_gmv,
    avg_recency_days

FROM segment_summary
ORDER BY customer_segment;


-- 5.5.3 用户分层结果完整性检查

SELECT
    COUNT(*) AS total_customers,
    COUNT(DISTINCT customer_unique_id) AS unique_customers,
    COUNT(DISTINCT customer_segment) AS segment_count,
    SUM(frequency) AS total_orders,
    ROUND(SUM(monetary), 2) AS total_gmv

FROM v_customer_rfm_segmented;