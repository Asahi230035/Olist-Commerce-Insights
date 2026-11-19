USE olist_analysis;

-- =========================================================
-- 第七阶段：统计分析与业务诊断
-- 7.1 统计数据基础检查
-- =========================================================

-- 7.1.1 查看配送与评价分析视图的字段结构
-- 目的：确认现有视图是否包含统计分析所需的变量
SHOW COLUMNS FROM v_delivery_review_analysis;


-- 7.1.2 检查订单粒度
-- 目的：确保一笔订单对应一行，防止重复记录影响统计结果
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT order_id) AS unique_orders,
    COUNT(*) - COUNT(DISTINCT order_id) AS duplicate_rows
FROM v_delivery_review_analysis;


-- 7.1.3 预览分析数据
-- 目的：检查字段内容、数据类型及缺失值情况
SELECT *
FROM v_delivery_review_analysis
LIMIT 5;

-- =========================================================
-- 7.2 统计样本质量检查
-- =========================================================

-- 7.2.1 检查评价数据的完整性与有效性
-- 目的：
-- 1. 确认有多少订单可以进入评分统计分析
-- 2. 检查评价记录数与评分是否匹配
-- 3. 确保评分位于合法范围 1~5

SELECT
    COUNT(*) AS total_orders,

    SUM(
        CASE WHEN review_count > 0
             AND avg_review_score IS NOT NULL
        THEN 1 ELSE 0 END
    ) AS valid_review_orders,

    SUM(
        CASE WHEN review_count = 0
             AND avg_review_score IS NULL
        THEN 1 ELSE 0 END
    ) AS missing_review_orders,

    SUM(
        CASE WHEN
            (review_count = 0 AND avg_review_score IS NOT NULL)
            OR
            (review_count > 0 AND avg_review_score IS NULL)
        THEN 1 ELSE 0 END
    ) AS inconsistent_review_orders,

    SUM(
        CASE WHEN avg_review_score < 1
               OR avg_review_score > 5
        THEN 1 ELSE 0 END
    ) AS invalid_score_orders

FROM v_delivery_review_analysis;


-- 7.2.2 检查延迟标记与延迟天数是否一致
-- 目的：保证后续分组分析与回归分析的变量可靠
-- 规则：delay_days > 0 应对应 is_delayed = 1

SELECT
    COUNT(*) AS total_orders,

    SUM(
        CASE WHEN is_delayed = 1
        THEN 1 ELSE 0 END
    ) AS delayed_orders,

    SUM(
        CASE WHEN is_delayed = 0
        THEN 1 ELSE 0 END
    ) AS ontime_orders,

    SUM(
        CASE WHEN delay_days IS NULL
               OR is_delayed NOT IN (0, 1)
               OR (delay_days > 0 AND is_delayed <> 1)
               OR (delay_days <= 0 AND is_delayed <> 0)
        THEN 1 ELSE 0 END
    ) AS inconsistent_delay_orders

FROM v_delivery_review_analysis;
-- =========================================================
-- 7.3 描述性统计分析
-- =========================================================

-- 7.3.1 导出订单级统计数据
-- 目的：为 Python 描述性统计、假设检验和回归分析提供数据
-- 粒度：一行对应一笔订单
-- 范围：沿用第六阶段的 96,203 笔有效配送订单
-- 说明：保留无评价订单，后续按分析目的筛选样本

SELECT
    order_id,
    customer_state,
    delivery_days,
    delay_days,
    is_delayed,
    review_count,
    avg_review_score
FROM v_delivery_review_analysis
ORDER BY order_id;
-- =========================================================
-- 7.5.3 扩展 Logistic 回归模型的数据准备
-- =========================================================

-- 目的：检查订单分析视图是否包含商品金额和购买时间
-- 后续通过 order_id 与配送评价视图进行一对一关联
-- 注意：本步骤只检查字段，不修改数据库结构

SHOW COLUMNS FROM v_order_analysis;
-- =========================================================
-- 7.5.3.1 扩展模型数据关联质量检查
-- =========================================================

-- 分析目的：
-- 将配送评价数据与订单商品金额、购买月份进行关联。
--
-- 关联方式：
-- 以配送评价视图为主表，使用 LEFT JOIN。
--
-- 数据粒度：
-- 一行对应一笔订单。
--
-- 核验重点：
-- 1. 关联前后订单数量是否一致
-- 2. 是否产生重复订单
-- 3. 商品金额和购买月份是否缺失
-- 4. 是否存在非法商品金额
-- 5. 是否仍然保留原有分析时间范围

SELECT
    COUNT(*) AS total_rows,

    COUNT(DISTINCT d.order_id) AS unique_orders,

    COUNT(*) - COUNT(DISTINCT d.order_id)
        AS duplicate_rows,

    -- 检查是否存在未匹配的订单
    SUM(
        CASE WHEN o.order_id IS NULL
        THEN 1 ELSE 0 END
    ) AS unmatched_orders,

    -- 检查商品金额缺失
    SUM(
        CASE WHEN o.item_price_total IS NULL
        THEN 1 ELSE 0 END
    ) AS missing_amount_orders,

    -- 检查非法负金额
    SUM(
        CASE WHEN o.item_price_total < 0
        THEN 1 ELSE 0 END
    ) AS negative_amount_orders,

    -- 检查零金额订单
    SUM(
        CASE WHEN o.item_price_total = 0
        THEN 1 ELSE 0 END
    ) AS zero_amount_orders,

    -- 检查购买月份缺失
    SUM(
        CASE WHEN o.purchase_month IS NULL
        THEN 1 ELSE 0 END
    ) AS missing_month_orders,

    -- 检查有效评价样本数量
    SUM(
        CASE
            WHEN d.review_count > 0
             AND d.avg_review_score IS NOT NULL
            THEN 1 ELSE 0
        END
    ) AS valid_review_orders,

    -- 检查月份覆盖范围
    COUNT(DISTINCT o.purchase_month) AS month_count,

    MIN(o.purchase_month) AS first_month,

    MAX(o.purchase_month) AS last_month

FROM v_delivery_review_analysis d

LEFT JOIN v_order_analysis o
    ON d.order_id = o.order_id;
-- =========================================================
-- 7.5.3.2 导出扩展 Logistic 回归分析数据
-- =========================================================

-- 目的：
-- 为后续多变量 Logistic 回归准备订单级数据。
--
-- 数据范围：
-- 2017-01 至 2018-08，最终已送达且配送时间有效的订单。
--
-- 样本口径：
-- 仅保留有有效评价的订单，预计 95,560 行。
--
-- 金额口径：
-- 商品金额，不含运费。
--
-- 注意：
-- 两个视图均为订单粒度，避免多表 JOIN 导致重复计数。

SELECT
    d.order_id,
    d.customer_state,
    d.delivery_days,
    d.delay_days,
    d.is_delayed,
    d.avg_review_score,

    -- 订单商品金额
    o.item_price_total AS order_amount,

    -- 订单购买月份
    o.purchase_month

FROM v_delivery_review_analysis d

INNER JOIN v_order_analysis o
    ON d.order_id = o.order_id

WHERE d.review_count > 0
  AND d.avg_review_score IS NOT NULL

ORDER BY d.order_id;