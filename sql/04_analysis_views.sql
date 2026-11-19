USE olist_analysis;

-- ==========================================
-- 04 标准分析视图
-- 1. 订单商品金额聚合
-- ==========================================

CREATE OR REPLACE VIEW v_order_items_agg AS

SELECT
    order_id,

    -- 商品明细行数
    COUNT(*) AS item_count,

    -- 不同商品数量
    COUNT(DISTINCT product_id) AS product_count,

    -- 不同商家数量
    COUNT(DISTINCT seller_id) AS seller_count,

    -- 商品金额
    SUM(price) AS item_price_total,

    -- 运费金额
    SUM(freight_value) AS freight_total,

    -- 商品金额 + 运费
    SUM(price + freight_value) AS item_amount_total

FROM order_items

GROUP BY order_id;
-- ==========================================
-- 2. 订单支付聚合
-- ==========================================

CREATE OR REPLACE VIEW v_payments_agg AS

SELECT
    order_id,

    -- 支付记录数量
    COUNT(*) AS payment_count,

    -- 支付金额总计
    SUM(payment_value) AS payment_total,

    -- 支付方式数量
    COUNT(DISTINCT payment_type) AS payment_type_count,

    -- 最大分期数
    MAX(payment_installments) AS max_installments

FROM order_payments

GROUP BY order_id;
-- ==========================================
-- 3. 订单评价聚合
-- ==========================================

CREATE OR REPLACE VIEW v_reviews_agg AS

SELECT
    order_id,

    -- 评价记录数量
    COUNT(*) AS review_count,

    -- 有效评价数量
    SUM(is_valid_score) AS valid_review_count,

    -- 平均评价评分
    ROUND(
        AVG(
            CASE
                WHEN is_valid_score = 1
                THEN review_score
            END
        ),
        2
    ) AS avg_review_score,

    -- 是否包含文字评价
    MAX(has_review_message) AS has_text_review

FROM v_reviews_clean

GROUP BY order_id;

SELECT
    'order_items' AS source_table,
    COUNT(*) AS order_count
FROM v_order_items_agg

UNION ALL

SELECT
    'payments',
    COUNT(*)
FROM v_payments_agg

UNION ALL

SELECT
    'reviews',
    COUNT(*)
FROM v_reviews_agg;

SELECT
    (SELECT SUM(price)
     FROM order_items) AS original_item_total,

    (SELECT SUM(item_price_total)
     FROM v_order_items_agg) AS aggregated_item_total,

    (SELECT SUM(payment_value)
     FROM order_payments) AS original_payment_total,

    (SELECT SUM(payment_total)
     FROM v_payments_agg) AS aggregated_payment_total;
-- ==========================================
-- 4. 订单级标准分析视图
-- ==========================================

CREATE OR REPLACE VIEW v_order_analysis AS

SELECT
    -- 1. 订单基本信息
    o.order_id,
    o.customer_id,
    c.customer_unique_id,

    o.order_status,

    -- 2. 客户地区
    c.customer_city,
    c.customer_state,
    c.customer_zip_code_prefix,

    -- 3. 订单时间
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    DATE(o.order_purchase_timestamp) AS purchase_date,

    DATE_FORMAT(
        o.order_purchase_timestamp,
        '%Y-%m'
    ) AS purchase_month,

    -- 4. 商品指标
    i.item_count,
    i.product_count,
    i.seller_count,

    i.item_price_total,
    i.freight_total,
    i.item_amount_total,

    -- 5. 支付指标
    p.payment_count,
    p.payment_total,
    p.payment_type_count,
    p.max_installments,

    -- 6. 评价指标
    r.review_count,
    r.valid_review_count,
    r.avg_review_score,
    r.has_text_review,

    -- 7. 订单数据完整性标记
    CASE
        WHEN i.order_id IS NULL
        THEN 0 ELSE 1
    END AS has_order_items,

    CASE
        WHEN p.order_id IS NULL
        THEN 0 ELSE 1
    END AS has_payment,

    CASE
        WHEN r.order_id IS NULL
        THEN 0 ELSE 1
    END AS has_review,

    -- 8. 配送指标
    o.delivery_days,
    o.is_late_delivery,
    o.is_valid_delivery,
    o.is_valid_transit,

    -- 9. 数据质量标记
    o.flag_missing_delivery,
    o.flag_canceled_delivered,
    o.flag_carrier_before_purchase,
    o.flag_delivery_before_carrier

FROM v_orders_clean o

LEFT JOIN customers c
    ON o.customer_id = c.customer_id

LEFT JOIN v_order_items_agg i
    ON o.order_id = i.order_id

LEFT JOIN v_payments_agg p
    ON o.order_id = p.order_id

LEFT JOIN v_reviews_agg r
    ON o.order_id = r.order_id;
SELECT
    COUNT(*) AS total_rows,

    COUNT(DISTINCT order_id) AS unique_orders,

    COUNT(*) - COUNT(DISTINCT order_id)
        AS duplicate_orders,

    SUM(has_order_items = 0)
        AS orders_without_items,

    SUM(has_payment = 0)
        AS orders_without_payment,

    SUM(has_review = 0)
        AS orders_without_review

FROM v_order_analysis;
SELECT
    SUM(item_price_total)
        AS total_item_price,

    SUM(freight_total)
        AS total_freight,

    SUM(item_amount_total)
        AS total_item_amount,

    SUM(payment_total)
        AS total_payment

FROM v_order_analysis;
SELECT
    order_id,
    customer_unique_id,
    order_status,
    purchase_month,
    item_count,
    item_price_total,
    freight_total,
    payment_total,
    avg_review_score,
    delivery_days,
    is_late_delivery

FROM v_order_analysis

LIMIT 10;
-- ==========================================
-- 5. 商品明细级标准分析视图
-- ==========================================

CREATE OR REPLACE VIEW v_order_item_analysis AS

SELECT
    -- 1. 商品明细标识
    oi.order_id,
    oi.order_item_id,

    -- 2. 商品信息
    oi.product_id,
    p.category_label,
    p.category_status,
    p.product_weight_g,
    p.is_valid_dimension,

    -- 3. 商家信息
    oi.seller_id,
    s.seller_city,
    s.seller_state,

    -- 4. 客户信息
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,

    -- 5. 订单信息
    o.order_status,
    o.order_purchase_timestamp,

    DATE_FORMAT(
        o.order_purchase_timestamp,
        '%Y-%m'
    ) AS purchase_month,

    -- 6. 金额指标
    oi.price AS item_price,
    oi.freight_value,

    (oi.price + oi.freight_value)
        AS item_total_amount,

    -- 7. 发货截止时间
    oi.shipping_limit_date

FROM order_items oi

LEFT JOIN v_products_clean p
    ON oi.product_id = p.product_id

LEFT JOIN sellers s
    ON oi.seller_id = s.seller_id

LEFT JOIN orders o
    ON oi.order_id = o.order_id

LEFT JOIN customers c
    ON o.customer_id = c.customer_id;
SELECT
    COUNT(*) AS total_rows,

    COUNT(DISTINCT order_id)
        AS unique_orders,

    COUNT(DISTINCT product_id)
        AS unique_products,

    COUNT(DISTINCT seller_id)
        AS unique_sellers,

    SUM(product_id IS NULL)
        AS missing_products,

    SUM(seller_id IS NULL)
        AS missing_sellers,

    SUM(customer_unique_id IS NULL)
        AS missing_customers

FROM v_order_item_analysis;
SELECT
    order_id,
    order_item_id,
    COUNT(*) AS record_count

FROM v_order_item_analysis

GROUP BY order_id, order_item_id

HAVING COUNT(*) > 1;
SELECT
    COUNT(*) AS total_items,

    SUM(item_price)
        AS total_item_price,

    SUM(freight_value)
        AS total_freight,

    SUM(item_total_amount)
        AS total_amount

FROM v_order_item_analysis;
-- ==========================================
-- 6. 客户级标准分析视图
-- 粒度：每个 customer_unique_id 一行
-- ==========================================

CREATE OR REPLACE VIEW v_customer_analysis AS

WITH customer_summary AS (

    SELECT
        customer_unique_id,

        -- 1. 所有订单数量
        COUNT(*) AS total_orders,

        -- 2. 已送达订单数量
        SUM(
            CASE
                WHEN order_status = 'delivered'
                THEN 1 ELSE 0
            END
        ) AS delivered_orders,

        -- 3. 已取消订单数量
        SUM(
            CASE
                WHEN order_status = 'canceled'
                THEN 1 ELSE 0
            END
        ) AS canceled_orders,

        -- 4. 首次与最近下单时间
        MIN(order_purchase_timestamp)
            AS first_order_at,

        MAX(order_purchase_timestamp)
            AS last_order_at,

        -- 5. 首次与最近已送达订单的购买时间
        MIN(
            CASE
                WHEN order_status = 'delivered'
                THEN order_purchase_timestamp
            END
        ) AS first_delivered_purchase_at,

        MAX(
            CASE
                WHEN order_status = 'delivered'
                THEN order_purchase_timestamp
            END
        ) AS last_delivered_purchase_at,

        -- 6. 已送达订单商品金额（不含运费）
        SUM(
            CASE
                WHEN order_status = 'delivered'
                THEN COALESCE(item_price_total, 0)
                ELSE 0
            END
        ) AS delivered_item_revenue,

        -- 7. 已送达且有商品明细的订单数量
        SUM(
            CASE
                WHEN order_status = 'delivered'
                     AND has_order_items = 1
                THEN 1 ELSE 0
            END
        ) AS delivered_orders_with_items

    FROM v_order_analysis

    GROUP BY customer_unique_id
),

latest_region AS (

    -- 取客户最近一笔订单对应的地区

    SELECT
        customer_unique_id,
        customer_city,
        customer_state,

        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY
                order_purchase_timestamp DESC,
                order_id DESC
        ) AS rn

    FROM v_order_analysis
)

SELECT
    s.*,

    -- 8. 已送达订单的平均商品金额
    ROUND(
        s.delivered_item_revenue /
        NULLIF(s.delivered_orders_with_items, 0),
        2
    ) AS avg_delivered_order_value,

    -- 9. 是否存在复购
    CASE
        WHEN s.delivered_orders >= 2
        THEN 1 ELSE 0
    END AS is_repeat_customer,

    -- 10. 客户最近订单所在地
    r.customer_city,
    r.customer_state

FROM customer_summary s

LEFT JOIN latest_region r
    ON s.customer_unique_id = r.customer_unique_id
    AND r.rn = 1;
SELECT
    COUNT(*) AS total_customers,

    COUNT(DISTINCT customer_unique_id)
        AS unique_customers,

    COUNT(*) - COUNT(DISTINCT customer_unique_id)
        AS duplicate_customers,

    SUM(total_orders)
        AS total_orders,

    SUM(delivered_orders)
        AS delivered_orders,

    SUM(canceled_orders)
        AS canceled_orders,

    SUM(is_repeat_customer)
        AS repeat_customers

FROM v_customer_analysis;
SELECT
    (
        SELECT SUM(item_price_total)
        FROM v_order_analysis
        WHERE order_status = 'delivered'
    ) AS original_delivered_revenue,

    (
        SELECT SUM(delivered_item_revenue)
        FROM v_customer_analysis
    ) AS customer_delivered_revenue;