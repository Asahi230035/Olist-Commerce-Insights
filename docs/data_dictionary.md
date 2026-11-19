# Olist 电商数据分析项目｜数据字典

## 1. 数据集概述

本项目使用 Brazilian E-Commerce Public Dataset by Olist，包含巴西电商平台的订单、客户、商品、商家、支付、评价和地理位置等数据。

数据来源：Kaggle — Brazilian E-Commerce Public Dataset by Olist

原始数据由 9 个 CSV 文件组成，导入 MySQL 数据库 `olist_analysis` 后进行质量检查与标准化处理。

本项目采用分层数据建模方式：

- **原始数据层**：保留导入后的原始业务记录。
- **标准化层**：通过 SQL 视图处理缺失值、异常时间、商品类别和地理位置问题。
- **分析视图层**：按订单、商品明细和客户等业务粒度组织分析数据。

所有清洗操作均保留原始数据，不直接覆盖原始表。

---

## 2. 原始数据表

### 2.1 customers｜客户表

**数据粒度：** 每行代表一条订单关联的客户记录。

**主键：** `customer_id`

| 字段 | 含义 |
|---|---|
| customer_id | 客户记录 ID，用于关联订单 |
| customer_unique_id | 真实客户唯一标识 |
| customer_zip_code_prefix | 客户邮编前缀 |
| customer_city | 客户所在城市 |
| customer_state | 客户所在州 |

注意：

`customer_id` 与 `customer_unique_id` 不同。同一真实客户可能存在多个 `customer_id`。

用户数量、复购和 RFM 分析使用 `customer_unique_id`。

### 2.2 orders｜订单表

**数据粒度：** 每行代表一个订单。

**主键：** `order_id`

| 字段 | 含义 |
|---|---|
| order_id | 订单唯一标识 |
| customer_id | 订单关联的客户记录 ID |
| order_status | 订单状态 |
| order_purchase_timestamp | 购买时间 |
| order_approved_at | 订单批准时间 |
| order_delivered_carrier_date | 交付承运商时间 |
| order_delivered_customer_date | 客户实际签收时间 |
| order_estimated_delivery_date | 预计送达日期 |

主要订单状态：

`delivered`、`shipped`、`canceled`、`unavailable`、`invoiced`、`processing`、`created`、`approved`。

### 2.3 order_items｜订单商品明细表

**数据粒度：** 每行代表订单中的一条商品明细。

**联合主键：** `(order_id, order_item_id)`

| 字段 | 含义 |
|---|---|
| order_id | 所属订单 ID |
| order_item_id | 订单内商品明细编号 |
| product_id | 商品 ID |
| seller_id | 商家 ID |
| shipping_limit_date | 商家发货截止时间 |
| price | 商品价格 |
| freight_value | 运费 |

注意：一个订单可能包含多条商品明细。

### 2.4 order_payments｜支付表

**数据粒度：** 每行代表一条订单支付记录。

**联合主键：** `(order_id, payment_sequential)`

| 字段 | 含义 |
|---|---|
| order_id | 所属订单 ID |
| payment_sequential | 订单内支付记录序号 |
| payment_type | 支付方式 |
| payment_installments | 分期数量 |
| payment_value | 支付金额 |

同一订单可能存在多条支付记录。

计算订单支付金额时，应先按 `order_id` 聚合。

### 2.5 order_reviews｜评价表

**数据粒度：** 每行代表一条评价记录。

**联合主键：** `(review_id, order_id)`

| 字段 | 含义 |
|---|---|
| review_id | 评价 ID |
| order_id | 所属订单 ID |
| review_score | 评价评分 |
| review_comment_title | 评论标题 |
| review_comment_message | 评论正文 |
| review_creation_date | 评价创建日期 |
| review_answer_timestamp | 评价回复时间 |

数据检查发现：

- `review_id` 存在重复。
- `(review_id, order_id)` 联合键满足唯一性。
- 一个订单可能对应多条评价记录。

评论文字缺失不代表评分无效。

### 2.6 products｜商品表

**数据粒度：** 每行代表一个商品。

**主键：** `product_id`

| 字段 | 含义 |
|---|---|
| product_id | 商品 ID |
| product_category_name | 商品原始类别 |
| product_name_lenght | 商品名称长度 |
| product_description_lenght | 商品描述长度 |
| product_photos_qty | 商品图片数量 |
| product_weight_g | 商品重量，单位克 |
| product_length_cm | 商品长度，单位厘米 |
| product_height_cm | 商品高度，单位厘米 |
| product_width_cm | 商品宽度，单位厘米 |

保留原始字段名中的 `lenght` 拼写，以保持与 CSV 一致。

### 2.7 sellers｜商家表

**数据粒度：** 每行代表一个商家。

**主键：** `seller_id`

| 字段 | 含义 |
|---|---|
| seller_id | 商家 ID |
| seller_zip_code_prefix | 商家邮编前缀 |
| seller_city | 商家所在城市 |
| seller_state | 商家所在州 |

### 2.8 geolocation｜地理位置表

**数据粒度：** 每行代表一条原始地理位置记录。

**数据库代理主键：** `geo_id`

| 字段 | 含义 |
|---|---|
| geo_id | 数据导入时生成的自增 ID |
| geolocation_zip_code_prefix | 邮编前缀 |
| geolocation_lat | 纬度 |
| geolocation_lng | 经度 |
| geolocation_city | 城市 |
| geolocation_state | 州 |

同一个邮编前缀可能对应多条地理位置记录，因此不能直接将其与客户或商家表连接后进行金额汇总。

### 2.9 category_translation｜商品类别翻译表

**数据粒度：** 每行代表一种商品类别的翻译映射。

**主键：** `product_category_name`

| 字段 | 含义 |
|---|---|
| product_category_name | 葡萄牙语类别名称 |
| product_category_name_english | 英语类别名称 |

---

## 3. 数据表关联关系

| 子表 | 关联字段 | 父表 | 关联字段 | 关系 |
|---|---|---|---|---|
| orders | customer_id | customers | customer_id | 多对一 |
| order_items | order_id | orders | order_id | 多对一 |
| order_items | product_id | products | product_id | 多对一 |
| order_items | seller_id | sellers | seller_id | 多对一 |
| order_payments | order_id | orders | order_id | 多对一 |
| order_reviews | order_id | orders | order_id | 多对一 |
| products | product_category_name | category_translation | product_category_name | 多对一（允许未匹配） |

地理位置表通过邮编前缀与客户或商家关联，但必须先转换为每个邮编一行的标准化数据。

### 多表关联风险

`order_items`、`order_payments` 和 `order_reviews` 都可能存在一个订单对应多条记录的情况。

如果直接连接这些明细表，容易造成订单记录膨胀及金额重复统计。

本项目采用先按订单聚合，再关联订单主表的方式解决该问题。

---

## 4. 标准化数据视图

标准化视图定义位于：

`sql/03_data_cleaning.sql`

| 视图 | 粒度 | 作用 |
|---|---|---|
| v_orders_clean | 订单 | 配送时间异常标记与有效性判断 |
| v_products_clean | 商品 | 商品类别标准化与尺寸有效性判断 |
| v_reviews_clean | 评价记录 | 评分有效性、文本完整性与重复关系标记 |
| v_geolocation_clean | 邮编前缀 | 地理位置去重、聚合与冲突标记 |

### 4.1 v_orders_clean

主要新增字段：

| 字段 | 含义 |
|---|---|
| flag_missing_delivery | 已送达但缺少签收时间 |
| flag_canceled_delivered | 已取消但存在签收时间 |
| flag_carrier_before_purchase | 承运商交接早于购买 |
| flag_delivery_before_carrier | 签收早于承运商交接 |
| is_valid_delivery | 是否满足购买至签收时长计算条件 |
| is_valid_transit | 是否满足承运商运输时长计算条件 |
| delivery_days | 购买至实际签收的天数 |
| is_late_delivery | 是否晚于预计送达日期 |

异常标记采用 0/1。

延迟状态在不满足计算条件时为 `NULL`。

### 4.2 v_products_clean

主要新增字段：

- `category_label`：标准化商品类别。
- `category_status`：类别数据质量状态。
- `is_valid_dimension`：重量和尺寸是否完整且为正值。

类别质量状态包括：

`valid`、`missing_category`、`missing_translation`。

### 4.3 v_reviews_clean

主要新增字段：

- `is_valid_score`：评分是否处于 1–5 分。
- `has_review_title`：是否具有非空标题。
- `has_review_message`：是否具有非空正文。
- `review_id_count`：相同评价 ID 的记录数量。
- `order_review_count`：同一订单的评价记录数量。
- `flag_invalid_answer_time`：回复时间是否早于创建时间。

### 4.4 v_geolocation_clean

**数据粒度：每个邮编前缀一行。**

主要字段：

`zip_code`、`city`、`state`、`latitude`、`longitude`、`source_record_count`、`city_count`、`state_count`、`location_quality_flag`。

地理位置质量状态：

`consistent`、`multi_city`、`multi_state`。

代表位置依据去重后的城市、州组合频率选择，经纬度为选中组合的平均坐标。

---

## 5. 标准分析视图

视图定义位于：

`sql/04_analysis_views.sql`

### 5.1 辅助聚合视图

| 视图 | 粒度 | 核心字段 |
|---|---|---|
| v_order_items_agg | 订单 | item_count、product_count、seller_count、item_price_total、freight_total、item_amount_total |
| v_payments_agg | 订单 | payment_count、payment_total、payment_type_count、max_installments |
| v_reviews_agg | 订单 | review_count、valid_review_count、avg_review_score、has_text_review |

### 5.2 v_order_analysis

**粒度：每个订单一行。**

核心字段分组：

- 订单信息：`order_id`、`customer_id`、`order_status`
- 客户信息：`customer_unique_id`、`customer_city`、`customer_state`
- 时间信息：`order_purchase_timestamp`、`purchase_date`、`purchase_month`
- 商品金额：`item_price_total`、`freight_total`、`item_amount_total`
- 支付信息：`payment_total`、`payment_count`
- 评价信息：`avg_review_score`、`review_count`
- 配送信息：`delivery_days`、`is_late_delivery`
- 完整性标记：`has_order_items`、`has_payment`、`has_review`

该视图是经营表现、订单状态和配送分析的主要数据基础。

### 5.3 v_order_item_analysis

**粒度：每个订单商品明细一行。**

核心字段：

`order_id`、`order_item_id`、`product_id`、`seller_id`、`category_label`、`category_status`、`item_price`、`freight_value`、`item_total_amount`、`customer_state`、`seller_state`、`purchase_month`。

该视图用于商品、类别、商家和地区销售分析。

订单级支付金额不直接复制到商品明细，避免重复汇总。

### 5.4 v_customer_analysis

**粒度：每个 customer_unique_id 一行。**

核心字段：

| 字段 | 含义 |
|---|---|
| customer_unique_id | 真实客户标识 |
| total_orders | 客户全部订单数 |
| delivered_orders | 已送达订单数 |
| canceled_orders | 已取消订单数 |
| first_order_at | 首次下单时间 |
| last_order_at | 最近下单时间 |
| first_delivered_purchase_at | 首次已送达订单的购买时间 |
| last_delivered_purchase_at | 最近已送达订单的购买时间 |
| delivered_item_revenue | 已送达订单商品金额，不含运费 |
| delivered_orders_with_items | 已送达且存在商品明细的订单数 |
| avg_delivered_order_value | 已送达且有商品明细订单的平均商品金额 |
| is_repeat_customer | 是否存在至少两笔已送达订单 |
| customer_city | 最近一笔订单记录的城市 |
| customer_state | 最近一笔订单记录的州 |

---

## 6. 数据完整性基准

以下结果来自第二阶段的数据导入与视图验证。

| 对象 | 记录数 |
|---|---:|
| orders | 99,441 |
| order_items | 112,650 |
| order_payments | 103,886 |
| order_reviews | 99,224 |
| products | 32,951 |
| sellers | 3,095 |
| geolocation | 1,000,163 |
| customers | 99,441 |
| category_translation | 71 |
| v_geolocation_clean | 19,015 |
| v_order_analysis | 99,441 |
| v_order_item_analysis | 112,650 |
| v_customer_analysis | 96,096 |

标准分析视图已完成基础记录数、唯一性及金额守恒检查。

---

## 7. 使用约定

1. 所有原始表保留，不直接覆盖或删除异常数据。
2. 订单经营分析优先使用 `v_order_analysis`。
3. 商品和类别分析优先使用 `v_order_item_analysis`。
4. 用户复购、客户价值分析优先使用 `v_customer_analysis`。
5. 地理位置关联使用 `v_geolocation_clean`，不直接关联原始百万行位置数据。
6. 涉及金额计算时，必须明确订单粒度、商品粒度以及运费是否包含在内。
7. 涉及配送分析时，必须按照指标要求使用对应的时间有效性标记。
8. 所有业务指标的正式计算口径统一记录在 `docs/metrics_definition.md`。
9. 数据清洗及异常处理方法统一记录在 `docs/methodology.md`。