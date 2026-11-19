-- =========================================
-- 05_business_performance.sql
-- 第三阶段：平台经营表现分析
-- =========================================

USE olist_analysis;

-- 3.1 月度数据覆盖检查

SELECT
    DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS order_month,

    COUNT(*) AS total_orders,

    SUM(order_status = 'delivered') AS delivered_orders,

    SUM(order_status = 'canceled') AS canceled_orders,

    COUNT(DISTINCT DATE(order_purchase_timestamp)) AS active_days,

    MIN(DATE(order_purchase_timestamp)) AS first_order_date,

    MAX(DATE(order_purchase_timestamp)) AS last_order_date

FROM orders

WHERE order_purchase_timestamp IS NOT NULL

GROUP BY DATE_FORMAT(order_purchase_timestamp, '%Y-%m')

ORDER BY order_month;
-- =========================================
-- 3.2 月度经营核心指标
-- =========================================

WITH order_amount AS (

    -- 先聚合到订单粒度，避免重复计算金额
    SELECT
        order_id,
        SUM(price) AS product_amount
    FROM order_items
    GROUP BY order_id

),

monthly_metrics AS (

    SELECT
        DATE_FORMAT(
            o.order_purchase_timestamp,
            '%Y-%m'
        ) AS order_month,

        COUNT(*) AS total_orders,

        SUM(o.order_status = 'delivered') AS delivered_orders,

        SUM(o.order_status = 'canceled') AS canceled_orders,

        SUM(
            CASE
                WHEN o.order_status = 'delivered'
                THEN COALESCE(a.product_amount, 0)
                ELSE 0
            END
        ) AS delivered_gmv,

        SUM(
            CASE
                WHEN o.order_status = 'delivered'
                     AND a.order_id IS NOT NULL
                THEN 1
                ELSE 0
            END
        ) AS valid_delivered_orders

    FROM orders o

    LEFT JOIN order_amount a
        ON o.order_id = a.order_id

    WHERE o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')

)

SELECT
    order_month,
    total_orders,
    delivered_orders,
    canceled_orders,

    ROUND(delivered_gmv, 2) AS delivered_gmv,

    ROUND(
        delivered_gmv / NULLIF(valid_delivered_orders, 0),
        2
    ) AS aov,

    ROUND(
        canceled_orders * 100.0 / NULLIF(total_orders, 0),
        2
    ) AS cancel_rate_pct

FROM monthly_metrics

ORDER BY order_month;
-- =========================================
-- 3.3 月度经营指标环比增长分析
-- =========================================

WITH order_amount AS (
    SELECT
        order_id,
        SUM(price) AS product_amount
    FROM order_items
    GROUP BY order_id
),

monthly_base AS (
    SELECT
        DATE_FORMAT(
            o.order_purchase_timestamp, '%Y-%m'
        ) AS order_month,

        COUNT(*) AS total_orders,

        SUM(o.order_status = 'delivered') AS delivered_orders,

        SUM(
            CASE
                WHEN o.order_status = 'delivered'
                THEN COALESCE(a.product_amount, 0)
                ELSE 0
            END
        ) AS delivered_gmv,

        SUM(
            CASE
                WHEN o.order_status = 'delivered'
                     AND a.order_id IS NOT NULL
                THEN 1 ELSE 0
            END
        ) AS valid_delivered_orders

    FROM orders o

    LEFT JOIN order_amount a
        ON o.order_id = a.order_id

    WHERE o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
),

monthly_metrics AS (
    SELECT
        *,
        delivered_gmv /
            NULLIF(valid_delivered_orders, 0) AS aov
    FROM monthly_base
),

monthly_lag AS (
    SELECT
        *,

        LAG(total_orders) OVER (
            ORDER BY order_month
        ) AS prev_orders,

        LAG(delivered_gmv) OVER (
            ORDER BY order_month
        ) AS prev_gmv,

        LAG(valid_delivered_orders) OVER (
            ORDER BY order_month
        ) AS prev_valid_orders,

        LAG(aov) OVER (
            ORDER BY order_month
        ) AS prev_aov

    FROM monthly_metrics
)

SELECT
    order_month,
    total_orders,
    valid_delivered_orders,

    ROUND(delivered_gmv, 2) AS delivered_gmv,
    ROUND(aov, 2) AS aov,

    CASE WHEN order_month >= '2017-03'
        THEN ROUND(
            (total_orders / NULLIF(prev_orders, 0) - 1) * 100,
            2
        )
    END AS orders_mom_pct,

    CASE WHEN order_month >= '2017-03'
        THEN ROUND(
            (valid_delivered_orders /
                NULLIF(prev_valid_orders, 0) - 1) * 100,
            2
        )
    END AS valid_orders_mom_pct,

    CASE WHEN order_month >= '2017-03'
        THEN ROUND(
            (delivered_gmv / NULLIF(prev_gmv, 0) - 1) * 100,
            2
        )
    END AS gmv_mom_pct,

    CASE WHEN order_month >= '2017-03'
        THEN ROUND(
            (aov / NULLIF(prev_aov, 0) - 1) * 100,
            2
        )
    END AS aov_mom_pct

FROM monthly_lag

ORDER BY order_month;
