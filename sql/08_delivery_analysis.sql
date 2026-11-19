-- 6.1 配送数据完整性检查
-- 6.1.1 已送达订单配送时间质量检查

-- 分析目的：
-- 检查已送达订单的配送时间字段是否完整、
-- 是否存在时间顺序异常，确定后续配送指标的有效样本。
-- 分析范围：2017-01 至 2018-08，最终状态为 delivered 的订单。
USE olist_analysis;

SELECT
    COUNT(*) AS delivered_orders,

    -- 缺少实际签收时间的订单
    SUM(
        order_delivered_customer_date IS NULL
    ) AS missing_delivery_time,

    -- 缺少预计送达时间的订单
    SUM(
        order_estimated_delivery_date IS NULL
    ) AS missing_estimated_time,

    -- 缺少交接承运商时间的订单
    SUM(
        order_delivered_carrier_date IS NULL
    ) AS missing_carrier_time,

    -- 实际签收时间早于购买时间
    SUM(
        order_delivered_customer_date IS NOT NULL
        AND order_delivered_customer_date < order_purchase_timestamp
    ) AS delivery_before_purchase,

    -- 交接承运商时间早于购买时间
    SUM(
        order_delivered_carrier_date IS NOT NULL
        AND order_delivered_carrier_date < order_purchase_timestamp
    ) AS carrier_before_purchase,

    -- 实际签收时间早于交接承运商时间
    SUM(
        order_delivered_customer_date IS NOT NULL
        AND order_delivered_carrier_date IS NOT NULL
        AND order_delivered_customer_date < order_delivered_carrier_date
    ) AS delivery_before_carrier,

    -- 可用于计算购买至签收时长的订单数
    SUM(
        order_delivered_customer_date IS NOT NULL
        AND order_delivered_customer_date >= order_purchase_timestamp
    ) AS valid_delivery_orders

FROM orders

WHERE order_status = 'delivered'
  AND order_purchase_timestamp >= '2017-01-01'
  AND order_purchase_timestamp < '2018-09-01';
-- 6.2 配送时长与延迟率分析
-- 6.2.1 平台整体配送效率指标
-- 统计有效配送订单的平均配送时长、准时送达率和延迟送达率。
-- 配送时长：实际签收时间 - 购买时间，单位为天。
-- 延迟判定：实际签收日期晚于预计送达日期。
-- 分析范围：2017-01 至 2018-08，最终已送达订单。

WITH valid_delivery AS (
    SELECT
        order_id,
        order_purchase_timestamp,
        order_delivered_customer_date,
        order_estimated_delivery_date,

        -- 计算购买至签收的实际配送时长
        TIMESTAMPDIFF(
            SECOND,
            order_purchase_timestamp,
            order_delivered_customer_date
        ) / 86400.0 AS delivery_days,

        -- 计算实际签收日期与预计送达日期的差值
        DATEDIFF(
            DATE(order_delivered_customer_date),
            DATE(order_estimated_delivery_date)
        ) AS delay_days

    FROM orders

    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'

      -- 排除缺少签收时间或配送时长不合法的订单
      AND order_delivered_customer_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp

      -- 确保预计送达日期存在
      AND order_estimated_delivery_date IS NOT NULL
)

SELECT
    COUNT(*) AS valid_delivery_orders,

    -- 平均实际配送时长
    ROUND(AVG(delivery_days), 2) AS avg_delivery_days,

    -- 最短与最长配送时长
    ROUND(MIN(delivery_days), 2) AS min_delivery_days,
    ROUND(MAX(delivery_days), 2) AS max_delivery_days,

    -- 准时或提前送达订单数
    SUM(delay_days <= 0) AS on_time_orders,

    -- 延迟送达订单数
    SUM(delay_days > 0) AS delayed_orders,

    -- 延迟送达率
    ROUND(
        100.0 * SUM(delay_days > 0) / COUNT(*),
        2
    ) AS delay_rate_pct,

    -- 仅统计延迟订单的平均延迟天数
    ROUND(
        AVG(
            CASE
                WHEN delay_days > 0 THEN delay_days
            END
        ),
        2
    ) AS avg_delay_days

FROM valid_delivery;
-- 6.2.2 配送时长分布分析
-- 将有效配送订单按实际配送时长划分为五个区间。
-- 统计各区间的订单数量、占比及延迟率。
-- 配送时长：购买时间至实际签收时间，单位为天。
-- 分析范围：2017-01 至 2018-08，最终已送达订单。

WITH delivery_data AS (
    SELECT
        order_id,

        TIMESTAMPDIFF(
            SECOND,
            order_purchase_timestamp,
            order_delivered_customer_date
        ) / 86400.0 AS delivery_days,

        -- 实际签收日期晚于预计日期视为延迟
        CASE
            WHEN DATE(order_delivered_customer_date)
                 > DATE(order_estimated_delivery_date)
            THEN 1
            ELSE 0
        END AS is_delayed

    FROM orders

    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
      AND order_delivered_customer_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
      AND order_estimated_delivery_date IS NOT NULL
),

delivery_groups AS (
    SELECT
        -- 使用数值编号保证配送区间按时长排序
        CASE
            WHEN delivery_days < 3 THEN 1
            WHEN delivery_days < 7 THEN 2
            WHEN delivery_days < 14 THEN 3
            WHEN delivery_days < 30 THEN 4
            ELSE 5
        END AS group_id,

        is_delayed

    FROM delivery_data
)

SELECT
    CASE group_id
        WHEN 1 THEN '0-3 days'
        WHEN 2 THEN '3-7 days'
        WHEN 3 THEN '7-14 days'
        WHEN 4 THEN '14-30 days'
        ELSE '30+ days'
    END AS delivery_group,

    COUNT(*) AS order_count,

    -- 当前时长区间的订单占比
    ROUND(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER (),
        2
    ) AS order_share_pct,

    -- 当前时长区间的延迟订单数
    SUM(is_delayed) AS delayed_orders,

    -- 当前时长区间内的延迟率
    ROUND(
        100.0 * SUM(is_delayed) / COUNT(*),
        2
    ) AS delay_rate_pct

FROM delivery_groups

GROUP BY group_id
ORDER BY group_id;

-- 6.2.3 延迟程度分布分析
-- 按实际签收日期超过预计送达日期的天数划分延迟等级。
-- 统计不同延迟等级的订单数量、占比及平均延迟天数。
-- 仅统计有效配送订单中实际发生延迟的订单。

WITH delayed_orders AS (
    SELECT
        order_id,

        -- 计算实际延迟天数
        DATEDIFF(
            DATE(order_delivered_customer_date),
            DATE(order_estimated_delivery_date)
        ) AS delay_days

    FROM orders

    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
      AND order_delivered_customer_date IS NOT NULL
      AND order_delivered_customer_date >= order_purchase_timestamp
      AND order_estimated_delivery_date IS NOT NULL
),

delay_groups AS (
    SELECT
        CASE
            WHEN delay_days BETWEEN 1 AND 3 THEN 1
            WHEN delay_days BETWEEN 4 AND 7 THEN 2
            WHEN delay_days BETWEEN 8 AND 14 THEN 3
            WHEN delay_days BETWEEN 15 AND 30 THEN 4
            ELSE 5
        END AS group_id,

        delay_days

    FROM delayed_orders

    -- 只保留实际延迟的订单
    WHERE delay_days > 0
),

group_summary AS (
    SELECT
        group_id,
        COUNT(*) AS delayed_orders,
        ROUND(AVG(delay_days), 2) AS avg_delay_days,
        MAX(delay_days) AS max_delay_days

    FROM delay_groups
    GROUP BY group_id
)

SELECT
    CASE group_id
        WHEN 1 THEN '1-3 days'
        WHEN 2 THEN '4-7 days'
        WHEN 3 THEN '8-14 days'
        WHEN 4 THEN '15-30 days'
        ELSE '31+ days'
    END AS delay_group,

    delayed_orders,

    -- 当前延迟等级占全部延迟订单的比例
    ROUND(
        100.0 * delayed_orders
        / SUM(delayed_orders) OVER (),
        2
    ) AS delayed_share_pct,

    avg_delay_days,
    max_delay_days

FROM group_summary
ORDER BY group_id;
-- 6.3 地区配送效率差异分析
-- 6.3.1 各买家州配送效率统计
-- 按买家所在州统计订单规模、实际配送时长、预计配送周期和延迟率。
-- 地区口径：customers.customer_state，按买家所在州归属订单。
-- 有效样本：2017-01 至 2018-08，最终已送达且配送时间有效的订单。


WITH delivery_data AS (
    SELECT
        o.order_id,
        c.customer_state,

        -- 实际配送时长：购买至签收，单位为天
        TIMESTAMPDIFF(
            SECOND,
            o.order_purchase_timestamp,
            o.order_delivered_customer_date
        ) / 86400.0 AS delivery_days,

        -- 预计配送周期：购买至预计送达日期，单位为天
        TIMESTAMPDIFF(
            SECOND,
            o.order_purchase_timestamp,
            o.order_estimated_delivery_date
        ) / 86400.0 AS estimated_days,

        -- 实际签收日期与预计送达日期之差
        DATEDIFF(
            DATE(o.order_delivered_customer_date),
            DATE(o.order_estimated_delivery_date)
        ) AS delay_days

    FROM orders o

    JOIN customers c
        ON o.customer_id = c.customer_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

      -- 与 6.2 保持相同的有效配送样本口径
      AND o.order_delivered_customer_date IS NOT NULL
      AND o.order_delivered_customer_date >= o.order_purchase_timestamp
      AND o.order_estimated_delivery_date IS NOT NULL
),

state_summary AS (
    SELECT
        customer_state,

        COUNT(*) AS total_orders,

        ROUND(
            AVG(delivery_days), 2
        ) AS avg_delivery_days,

        ROUND(
            AVG(estimated_days), 2
        ) AS avg_estimated_days,

        -- 实际签收日期晚于预计日期的订单数量
        SUM(delay_days > 0) AS delayed_orders,

        -- 州内延迟率，分母为该州有效配送订单数
        ROUND(
            100.0 * SUM(delay_days > 0) / COUNT(*),
            2
        ) AS delay_rate_pct,

        -- 仅对发生延迟的订单计算平均延迟天数
        ROUND(
            AVG(
                CASE
                    WHEN delay_days > 0 THEN delay_days
                END
            ), 2
        ) AS avg_delay_days

    FROM delivery_data
    GROUP BY customer_state
)

SELECT
    customer_state,
    total_orders,

    -- 各州订单量占全部有效配送订单的比例
    ROUND(
        100.0 * total_orders
        / SUM(total_orders) OVER (),
        2
    ) AS order_share_pct,

    avg_delivery_days,
    avg_estimated_days,
    delayed_orders,
    delay_rate_pct,
    avg_delay_days

FROM state_summary

-- 优先观察订单规模较大的地区
ORDER BY total_orders DESC;

-- 6.4 配送效率与用户评分关联分析
-- 6.4.1 构建配送与评价联合分析视图
-- 将用户评分聚合到订单级，再关联有效配送订单。
-- 保留未评价订单，避免仅统计有评价订单造成样本口径不清。
-- 评价指标：一个订单存在多条评价时，使用该订单的平均评分。
-- 分析范围：2017-01 至 2018-08，最终已送达且配送时间有效的订单。

CREATE OR REPLACE VIEW v_delivery_review_analysis AS

WITH review_summary AS (
    SELECT
        order_id,
        COUNT(*) AS review_count,
        AVG(review_score) AS avg_review_score

    FROM order_reviews
    GROUP BY order_id
)

SELECT
    o.order_id,
    c.customer_state,

    -- 实际配送时长，单位为天
    TIMESTAMPDIFF(
        SECOND,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date
    ) / 86400.0 AS delivery_days,

    -- 实际签收日期与预计送达日期的差值
    DATEDIFF(
        DATE(o.order_delivered_customer_date),
        DATE(o.order_estimated_delivery_date)
    ) AS delay_days,

    -- 订单是否延迟送达
    CASE
        WHEN DATE(o.order_delivered_customer_date)
             > DATE(o.order_estimated_delivery_date)
        THEN 1
        ELSE 0
    END AS is_delayed,

    COALESCE(r.review_count, 0) AS review_count,
    r.avg_review_score

FROM orders o

JOIN customers c
    ON o.customer_id = c.customer_id

LEFT JOIN review_summary r
    ON o.order_id = r.order_id

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp < '2018-09-01'
  AND o.order_delivered_customer_date IS NOT NULL
  AND o.order_delivered_customer_date >= o.order_purchase_timestamp
  AND o.order_estimated_delivery_date IS NOT NULL;


-- 6.4.2 准时订单与延迟订单的用户评分对比
-- 比较两类订单的平均评分、评价覆盖率和低评分占比。
-- 低评分定义：订单平均评分低于 3 分。
-- 平均评分及低评分占比仅以有评价的订单为分母。

SELECT
    CASE
        WHEN is_delayed = 0 THEN 'On-time'
        ELSE 'Delayed'
    END AS delivery_status,

    COUNT(*) AS total_orders,

    -- 有评价与无评价的订单数量
    COUNT(avg_review_score) AS reviewed_orders,

    SUM(avg_review_score IS NULL) AS missing_review_orders,

    ROUND(
        100.0 * COUNT(avg_review_score) / COUNT(*),
        2
    ) AS review_coverage_pct,

    -- 订单等权平均评分
    ROUND(
        AVG(avg_review_score),
        2
    ) AS avg_review_score,

    -- 低评分订单数量及其在已评价订单中的占比
    SUM(
        CASE
            WHEN avg_review_score < 3 THEN 1
            ELSE 0
        END
    ) AS low_score_orders,

    ROUND(
        100.0 * SUM(
            CASE
                WHEN avg_review_score < 3 THEN 1
                ELSE 0
            END
        ) / NULLIF(COUNT(avg_review_score), 0),
        2
    ) AS low_score_rate_pct

FROM v_delivery_review_analysis

GROUP BY is_delayed
ORDER BY is_delayed;

-- 6.4.3 不同延迟程度与用户评分分析
-- 按延迟天数划分订单，比较不同延迟等级的用户评分和低评分率。
-- 准时或提前送达订单作为对照组。
-- 低评分定义：订单平均评分低于 3 分。
-- 评分及低评分率仅统计有评价的订单。

WITH delay_groups AS (
    SELECT
        order_id,
        avg_review_score,

        -- 根据延迟天数划分配送状态
        CASE
            WHEN delay_days <= 0 THEN 0
            WHEN delay_days BETWEEN 1 AND 3 THEN 1
            WHEN delay_days BETWEEN 4 AND 7 THEN 2
            WHEN delay_days BETWEEN 8 AND 14 THEN 3
            WHEN delay_days BETWEEN 15 AND 30 THEN 4
            ELSE 5
        END AS group_id

    FROM v_delivery_review_analysis
),

group_summary AS (
    SELECT
        group_id,

        COUNT(*) AS total_orders,

        -- 有评价订单数量
        COUNT(avg_review_score) AS reviewed_orders,

        -- 评价覆盖率
        ROUND(
            100.0 * COUNT(avg_review_score) / COUNT(*),
            2
        ) AS review_coverage_pct,

        -- 订单等权平均评分
        ROUND(
            AVG(avg_review_score),
            2
        ) AS avg_review_score,

        -- 低评分订单数量
        SUM(
            CASE
                WHEN avg_review_score < 3 THEN 1
                ELSE 0
            END
        ) AS low_score_orders

    FROM delay_groups
    GROUP BY group_id
)

SELECT
    CASE group_id
        WHEN 0 THEN 'On-time'
        WHEN 1 THEN '1-3 days'
        WHEN 2 THEN '4-7 days'
        WHEN 3 THEN '8-14 days'
        WHEN 4 THEN '15-30 days'
        ELSE '31+ days'
    END AS delay_group,

    total_orders,
    reviewed_orders,
    review_coverage_pct,
    avg_review_score,
    low_score_orders,

    -- 低评分率：低评分订单数 / 有评价订单数
    ROUND(
        100.0 * low_score_orders
        / NULLIF(reviewed_orders, 0),
        2
    ) AS low_score_rate_pct

FROM group_summary
ORDER BY group_id;