-- 订单状态与实际送达时间的关系
 USE olist_analysis;
SELECT
    order_status,
    COUNT(*) AS total_orders,

    SUM(
        CASE
            WHEN order_delivered_customer_date IS NULL
            THEN 1 ELSE 0
        END
    ) AS missing_delivery_date,

    SUM(
        CASE
            WHEN order_delivered_customer_date IS NOT NULL
            THEN 1 ELSE 0
        END
    ) AS has_delivery_date

FROM orders
GROUP BY order_status
ORDER BY total_orders DESC;
-- 商品价格与运费检查

SELECT
    COUNT(*) AS total_items,
    SUM(price IS NULL) AS missing_price,
    SUM(price < 0) AS negative_price,
    SUM(freight_value IS NULL) AS missing_freight,
    SUM(freight_value < 0) AS negative_freight
FROM order_items;


-- 支付金额检查

SELECT
    COUNT(*) AS total_payments,
    SUM(payment_value IS NULL) AS missing_payment,
    SUM(payment_value < 0) AS negative_payment
FROM order_payments;
-- 订单时间先后顺序检查

SELECT
    COUNT(*) AS total_orders,

    SUM(
        order_approved_at < order_purchase_timestamp
    ) AS approval_before_purchase,

    SUM(
        order_delivered_carrier_date < order_purchase_timestamp
    ) AS carrier_before_purchase,

    SUM(
        order_delivered_customer_date < order_purchase_timestamp
    ) AS delivery_before_purchase,

    SUM(
        order_delivered_customer_date < order_delivered_carrier_date
    ) AS delivery_before_carrier

FROM orders;
-- ======================================
-- 订单时间异常程度分析
-- ======================================

WITH time_anomalies AS (

    -- 承运商时间早于购买时间
    SELECT
        'carrier_before_purchase' AS anomaly_type,
        TIMESTAMPDIFF(
            MINUTE,
            order_delivered_carrier_date,
            order_purchase_timestamp
        ) AS difference_minutes
    FROM orders
    WHERE order_delivered_carrier_date
          < order_purchase_timestamp

    UNION ALL

    -- 实际送达时间早于承运商时间
    SELECT
        'delivery_before_carrier' AS anomaly_type,
        TIMESTAMPDIFF(
            MINUTE,
            order_delivered_customer_date,
            order_delivered_carrier_date
        ) AS difference_minutes
    FROM orders
    WHERE order_delivered_customer_date
          < order_delivered_carrier_date
)

SELECT
    anomaly_type,
    COUNT(*) AS total_anomalies,

    SUM(difference_minutes <= 60)
        AS within_1_hour,

    SUM(
        difference_minutes > 60
        AND difference_minutes <= 1440
    ) AS within_1_day,

    SUM(difference_minutes > 1440)
        AS over_1_day,

    MIN(difference_minutes)
        AS min_difference_minutes,

    MAX(difference_minutes)
        AS max_difference_minutes

FROM time_anomalies
GROUP BY anomaly_type;
-- 查看时间差最大的异常订单

WITH anomalies AS (

    SELECT
        order_id,
        order_status,
        order_purchase_timestamp,
        order_delivered_carrier_date,
        order_delivered_customer_date,

        'carrier_before_purchase' AS anomaly_type,

        TIMESTAMPDIFF(
            MINUTE,
            order_delivered_carrier_date,
            order_purchase_timestamp
        ) AS difference_minutes

    FROM orders

    WHERE order_delivered_carrier_date
          < order_purchase_timestamp

    UNION ALL

    SELECT
        order_id,
        order_status,
        order_purchase_timestamp,
        order_delivered_carrier_date,
        order_delivered_customer_date,

        'delivery_before_carrier' AS anomaly_type,

        TIMESTAMPDIFF(
            MINUTE,
            order_delivered_customer_date,
            order_delivered_carrier_date
        ) AS difference_minutes

    FROM orders

    WHERE order_delivered_customer_date
          < order_delivered_carrier_date
)

SELECT
    *,
    ROUND(difference_minutes / 1440, 2)
        AS difference_days

FROM anomalies

ORDER BY difference_minutes DESC

LIMIT 15;