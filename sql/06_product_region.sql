-- =========================================
-- 06_product_region.sql
-- 第四阶段：商品与地区分析
-- =========================================

USE olist_analysis;

-- =========================================
-- 4.1 商品品类销售贡献分析
-- =========================================

WITH category_sales AS (

    SELECT
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS category_name,

        COUNT(*) AS item_count,

        COUNT(DISTINCT oi.product_id) AS product_count,

        COUNT(DISTINCT oi.order_id) AS order_count,

        SUM(oi.price) AS gmv,

        AVG(oi.price) AS avg_item_price

    FROM order_items oi

    JOIN orders o
        ON oi.order_id = o.order_id

    LEFT JOIN products p
        ON oi.product_id = p.product_id

    LEFT JOIN category_translation ct
        ON p.product_category_name =
           ct.product_category_name

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY category_name

)

SELECT
    category_name,

    item_count,

    product_count,

    order_count,

    ROUND(gmv, 2) AS gmv,

    ROUND(avg_item_price, 2) AS avg_item_price,

    ROUND(
        gmv * 100.0 / SUM(gmv) OVER (),
        2
    ) AS gmv_share_pct

FROM category_sales

ORDER BY gmv DESC

LIMIT 15;
-- 商品品类分析金额基准核验

SELECT
    COUNT(*) AS item_rows,

    COUNT(DISTINCT oi.order_id) AS orders_with_items,

    COUNT(DISTINCT oi.product_id) AS unique_products,

    ROUND(SUM(oi.price), 2) AS total_gmv

FROM order_items oi

JOIN orders o
    ON oi.order_id = o.order_id

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp < '2018-09-01';
-- =========================================
-- 4.1.2 品类关联完整性检查
-- =========================================

WITH base AS (
    SELECT
        oi.order_id,
        oi.order_item_id,
        oi.product_id,
        oi.price
    FROM order_items oi
    JOIN orders o
        ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'
),

category_joined AS (
    SELECT
        b.order_id,
        b.order_item_id,
        b.price,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS category_name
    FROM base b
    LEFT JOIN products p
        ON b.product_id = p.product_id
    LEFT JOIN category_translation ct
        ON p.product_category_name =
           ct.product_category_name
)

SELECT
    (SELECT COUNT(*) FROM base) AS base_rows,

    COUNT(*) AS joined_rows,

    (SELECT ROUND(SUM(price), 2) FROM base) AS base_gmv,

    ROUND(SUM(price), 2) AS joined_gmv,

    COUNT(DISTINCT category_name) AS category_count,

    SUM(category_name = 'unknown') AS unknown_item_rows

FROM category_joined;
-- =========================================
-- 4.1.3 商品品类月度结构变化
-- 比较 2018-07 与 2018-08
-- =========================================

WITH monthly_category AS (

    SELECT
        DATE_FORMAT(
            o.order_purchase_timestamp, '%Y-%m'
        ) AS order_month,

        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS category_name,

        COUNT(*) AS item_count,

        SUM(oi.price) AS gmv

    FROM order_items oi

    JOIN orders o
        ON oi.order_id = o.order_id

    LEFT JOIN products p
        ON oi.product_id = p.product_id

    LEFT JOIN category_translation ct
        ON p.product_category_name =
           ct.product_category_name

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2018-07-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY order_month, category_name
),

category_comparison AS (

    SELECT
        category_name,

        SUM(
            CASE WHEN order_month = '2018-07'
            THEN item_count ELSE 0 END
        ) AS july_items,

        SUM(
            CASE WHEN order_month = '2018-08'
            THEN item_count ELSE 0 END
        ) AS aug_items,

        SUM(
            CASE WHEN order_month = '2018-07'
            THEN gmv ELSE 0 END
        ) AS july_gmv,

        SUM(
            CASE WHEN order_month = '2018-08'
            THEN gmv ELSE 0 END
        ) AS aug_gmv

    FROM monthly_category

    GROUP BY category_name
)

SELECT
    category_name,

    july_items,
    aug_items,

    ROUND(july_gmv, 2) AS july_gmv,
    ROUND(aug_gmv, 2) AS aug_gmv,

    ROUND(
        aug_gmv - july_gmv, 2
    ) AS gmv_change,

    ROUND(
        july_gmv * 100.0 /
        NULLIF(SUM(july_gmv) OVER (), 0), 2
    ) AS july_share_pct,

    ROUND(
        aug_gmv * 100.0 /
        NULLIF(SUM(aug_gmv) OVER (), 0), 2
    ) AS aug_share_pct

FROM category_comparison

ORDER BY ABS(aug_gmv - july_gmv) DESC

LIMIT 15;
-- =========================================
-- 4.1.4 AOV 结构分解
-- 比较 2018-07 与 2018-08
-- =========================================

WITH order_level AS (

    SELECT
        DATE_FORMAT(
            o.order_purchase_timestamp, '%Y-%m'
        ) AS order_month,

        o.order_id,

        COUNT(oi.order_item_id) AS item_count,

        SUM(oi.price) AS order_amount

    FROM orders o

    JOIN order_items oi
        ON o.order_id = oi.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2018-07-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        order_month,
        o.order_id
)

SELECT
    order_month,

    COUNT(*) AS valid_orders,

    SUM(item_count) AS total_items,

    ROUND(
        SUM(order_amount), 2
    ) AS gmv,

    ROUND(
        SUM(item_count) * 1.0 / COUNT(*), 4
    ) AS items_per_order,

    ROUND(
        SUM(order_amount) / SUM(item_count), 2
    ) AS avg_item_price,

    ROUND(
        SUM(order_amount) / COUNT(*), 2
    ) AS aov

FROM order_level

GROUP BY order_month

ORDER BY order_month;
-- =========================================
-- 4.2.1 商家销售贡献分析
-- =========================================

WITH seller_sales AS (

    SELECT
        oi.seller_id,

        COUNT(*) AS item_count,

        COUNT(DISTINCT oi.order_id) AS order_count,

        COUNT(DISTINCT oi.product_id) AS product_count,

        SUM(oi.price) AS gmv,

        AVG(oi.price) AS avg_item_price

    FROM order_items oi

    JOIN orders o
        ON oi.order_id = o.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY oi.seller_id

)

SELECT
    seller_id,

    item_count,

    order_count,

    product_count,

    ROUND(gmv, 2) AS gmv,

    ROUND(avg_item_price, 2) AS avg_item_price,

    ROUND(
        gmv * 100.0 / SUM(gmv) OVER (),
        2
    ) AS gmv_share_pct

FROM seller_sales

ORDER BY gmv DESC

LIMIT 15;
-- =========================================
-- 4.2.2 商家销售集中度分析
-- =========================================

WITH seller_sales AS (

    SELECT
        oi.seller_id,
        SUM(oi.price) AS gmv

    FROM order_items oi

    JOIN orders o
        ON oi.order_id = o.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY oi.seller_id

),

ranked_sellers AS (

    SELECT
        seller_id,
        gmv,

        ROW_NUMBER() OVER (
            ORDER BY gmv DESC, seller_id
        ) AS seller_rank

    FROM seller_sales

)

SELECT
    COUNT(*) AS active_sellers,

    ROUND(SUM(gmv), 2) AS total_gmv,

    ROUND(
        SUM(CASE WHEN seller_rank <= 5
            THEN gmv ELSE 0 END)
        / NULLIF(SUM(gmv), 0) * 100, 2
    ) AS top5_share_pct,

    ROUND(
        SUM(CASE WHEN seller_rank <= 10
            THEN gmv ELSE 0 END)
        / NULLIF(SUM(gmv), 0) * 100, 2
    ) AS top10_share_pct,

    ROUND(
        SUM(CASE WHEN seller_rank <= 15
            THEN gmv ELSE 0 END)
        / NULLIF(SUM(gmv), 0) * 100, 2
    ) AS top15_share_pct,

    ROUND(
        SUM(CASE WHEN seller_rank <= 50
            THEN gmv ELSE 0 END)
        / NULLIF(SUM(gmv), 0) * 100, 2
    ) AS top50_share_pct

FROM ranked_sellers;

-- =========================================
-- 4.3.1 买家地区经营表现分析
-- =========================================

WITH order_amount AS (

    -- 商品金额先聚合到订单级
    SELECT
        order_id,
        SUM(price) AS product_amount

    FROM order_items

    GROUP BY order_id

),

state_sales AS (

    SELECT
        COALESCE(
            NULLIF(TRIM(c.customer_state), ''),
            'unknown'
        ) AS customer_state,

        COUNT(*) AS valid_orders,

        COUNT(DISTINCT c.customer_unique_id)
            AS unique_customers,

        SUM(a.product_amount) AS gmv,

        AVG(a.product_amount) AS aov

    FROM orders o

    JOIN customers c
        ON o.customer_id = c.customer_id

    JOIN order_amount a
        ON o.order_id = a.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        COALESCE(
            NULLIF(TRIM(c.customer_state), ''),
            'unknown'
        )

)

SELECT
    customer_state,

    valid_orders,

    unique_customers,

    ROUND(gmv, 2) AS gmv,

    ROUND(aov, 2) AS aov,

    ROUND(
        gmv * 100.0 / SUM(gmv) OVER (),
        2
    ) AS gmv_share_pct

FROM state_sales

ORDER BY gmv DESC;
-- =========================================
-- 4.3.3 地区商品品类偏好分析
-- Top 5 州 × Top 3 商品品类
-- =========================================

WITH state_category AS (

    SELECT
        c.customer_state,

        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'unknown'
        ) AS category_name,

        COUNT(*) AS item_count,

        COUNT(DISTINCT oi.order_id) AS order_count,

        SUM(oi.price) AS gmv

    FROM order_items oi

    JOIN orders o
        ON oi.order_id = o.order_id

    JOIN customers c
        ON o.customer_id = c.customer_id

    LEFT JOIN products p
        ON oi.product_id = p.product_id

    LEFT JOIN category_translation ct
        ON p.product_category_name =
           ct.product_category_name

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'
      AND c.customer_state IN (
          'SP', 'RJ', 'MG', 'RS', 'PR'
      )

    GROUP BY
        c.customer_state,
        category_name
),

ranked_categories AS (

    SELECT
        customer_state,
        category_name,
        item_count,
        order_count,
        gmv,

        ROW_NUMBER() OVER (
            PARTITION BY customer_state
            ORDER BY gmv DESC, category_name
        ) AS category_rank,

        SUM(gmv) OVER (
            PARTITION BY customer_state
        ) AS state_total_gmv

    FROM state_category
)

SELECT
    customer_state,
    category_rank,
    category_name,

    item_count,
    order_count,

    ROUND(gmv, 2) AS gmv,

    ROUND(
        gmv * 100.0 / NULLIF(state_total_gmv, 0),
        2
    ) AS state_category_share_pct

FROM ranked_categories

WHERE category_rank <= 3

ORDER BY
    customer_state,
    category_rank;
-- =========================================
-- 4.3.4 商家地域分布分析
-- =========================================

WITH seller_state_sales AS (

    SELECT
        COALESCE(
            NULLIF(TRIM(s.seller_state), ''),
            'unknown'
        ) AS seller_state,

        COUNT(DISTINCT oi.seller_id) AS active_sellers,

        COUNT(DISTINCT oi.order_id) AS order_count,

        SUM(oi.price) AS gmv

    FROM order_items oi

    JOIN orders o
        ON oi.order_id = o.order_id

    JOIN sellers s
        ON oi.seller_id = s.seller_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        COALESCE(
            NULLIF(TRIM(s.seller_state), ''),
            'unknown'
        )
)

SELECT
    seller_state,

    active_sellers,

    order_count,

    ROUND(gmv, 2) AS gmv,

    ROUND(
        gmv * 100.0 / SUM(gmv) OVER (),
        2
    ) AS gmv_share_pct,

    ROUND(
        active_sellers * 100.0 /
        SUM(active_sellers) OVER (),
        2
    ) AS seller_share_pct

FROM seller_state_sales

ORDER BY gmv DESC;