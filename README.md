# Olist 电商平台经营与用户体验分析

## 一、研究背景

电商平台的经营状况不能仅通过订单数量衡量。订单规模、客单价、商品结构、商家与地区分布共同影响交易表现，配送效率和用户评价则反映了交易完成后的履约体验。

Olist 巴西电商公开数据集包含客户、订单、商品明细、支付、评价、商品、商家和地理位置等记录，为研究平台经营与用户体验提供了较完整的交易链路。但原始数据同时存在一对多关联、时间异常、类别缺失和重复地理位置等问题，需要先建立统一的数据处理和指标计算口径，再开展业务分析。

本项目模拟数据分析师的完整工作流程，从原始数据出发，依次完成数据检查、标准化建模、业务分析、统计验证和报告整理，为理解平台历史经营结构及履约问题提供依据。

## 二、项目概览

项目主分析期间为 **2017 年 1 月至 2018 年 8 月**，使用 MySQL 和 Python 构建完整分析流程，主要研究四个方面的问题：

1. **平台经营表现：** 月度订单量、商品交易额、客单价和取消率如何变化，交易额变化体现为订单规模还是客单价变化。
2. **商品、商家与地区结构：** 哪些品类、商家和地区贡献了主要交易额，买家与商家的地域分布是否存在差异。
3. **客户购买行为与价值：** 客户购买频次和复购情况如何，不同 RFM 客户群的人数与交易贡献有何区别。
4. **配送效率与用户体验：** 配送时长和延迟呈现怎样的分布，配送延迟与用户低评分之间是否存在稳定的统计关联。

在描述性业务分析的基础上，项目进一步使用假设检验、多变量 Logistic 回归和敏感性分析，对配送延迟与低评分之间的关系进行统计研究。

数据来源：[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)。

## 三、技术路线

项目整体流程为：

**原始 CSV 数据 → pandas 数据初检 → MySQL 建表与数据导入 → 数据质量检查 → 标准化视图 → 业务分析视图 → SQL 指标计算 → Python 可视化与统计分析 → 阶段报告与综合报告**

主要技术工具包括：

- **MySQL 8.4：** 数据存储、质量检查、标准化处理、分析视图和业务指标计算。
- **SQLAlchemy / PyMySQL：** 连接 Python 与 MySQL，完成原始数据分批导入。
- **pandas / NumPy：** 数据读取、检查、转换和统计计算。
- **Matplotlib：** 经营趋势、商品结构、客户分层和配送评价可视化。
- **SciPy / statsmodels：** 卡方检验、Mann–Whitney U 检验、效应量估计和 Logistic 回归。
- **JupyterLab：** 组织分析过程、核验数据和展示图表。

数据处理遵循“**保留原始记录、增加质量标记、按指标选择有效样本**”的原则。商品明细、支付和评价均先聚合到订单粒度后再关联，避免一对多连接造成订单数量或金额重复计算。

## 四、项目结构

```text
olist-ecommerce-analysis/
│
├── README.md
│   └── 项目背景、研究内容、结构及主要结论
│
├── requirements.txt
│   └── Python 环境依赖
│
├── data/（考虑到文件大小请自行下载运行相应脚本获取）
│   ├── raw/
│   │   └── Olist原始数据
│   │
│   └── processed/
│       ├── monthly_business_performan）ce.csv
│       ├── category_sales_top15.csv
│       ├── category_gmv_change.csv
│       ├── seller_sales_top15.csv
│       ├── seller_concentration.csv
│       ├── customer_state_sales.csv
│       ├── seller_state_sales.csv
│       ├── customer_rfm_segments.csv
│       ├── delivery_state_summary.csv
│       ├── delivery_review_by_delay.csv
│       ├── delivery_review_statistical.csv
│       └── delivery_review_regression.csv
├── docs/
│   ├── data_dictionary.md
│   │   └── 数据表、字段、关联关系、业务粒度和视图说明
│   ├── metrics_definition.md
│   │   └── GMV、AOV、复购率、RFM、配送和评分指标口径
│   └── methodology.md
│       └── 数据清洗、异常处理、分析建模和验证原则
│
├── src/
│   └── data_loader.py
│       └── 将原始 CSV 分批导入 MySQL，并核验导入记录数
│
├── sql/
│   ├── 01_create_tables.sql
│   │   └── 创建数据库及 9 张原始数据表
│   ├── 02_data_quality.sql
│   │   └── 检查金额、缺失值、订单状态和时间异常
│   ├── 03_data_cleaning.sql
│   │   └── 创建订单、商品、评价和地理位置标准化视图
│   ├── 04_analysis_views.sql
│   │   └── 创建订单、商品明细和客户级标准分析视图
│   ├── 05_business_performance.sql
│   │   └── 月度经营指标、环比增长和 GMV 量价分析
│   ├── 06_product_region.sql
│   │   └── 品类、商家、买家地区和商家地区分析
│   ├── 07_customer_analysis.sql
│   │   └── 客户购买频次、RFM 评分及七类客户分层
│   ├── 08_delivery_analysis.sql
│   │   └── 配送效率、地区延迟和配送评分联合分析
│   ├── 09_statistical_analysis.sql
│   │   └── 统计样本检查及回归分析数据准备
│   └── 010_inspect_views-partly.sql
│       └── 主要数据库视图的抽样检查
│
├── notebooks/
│   ├── 01_data_profiling.ipynb
│   │   └── 原始数据维度、缺失值、主键及关联关系检查
│   ├── 02_business_analysis.ipynb
│   │   └── 经营趋势、GMV、AOV 和环比增长可视化
│   ├── 03_product_region.ipynb
│   │   └── 品类、商家及地区结构可视化
│   ├── 04_customer_analysis.ipynb
│   │   └── RFM 客户分层结果核验与可视化
│   ├── 05_delivery_review.ipynb
│   │   └── 地区延迟率、延迟程度和用户评分可视化
│   └── 06_statistical_analysis.ipynb
│       └── 描述统计、假设检验、Logistic 回归和敏感性分析
│
└── reports/
    ├── figures/
    │   └── 各分析阶段生成的 20 张图表
    ├── business_performance_summary.md
    │   └── 平台经营表现阶段报告
    ├── product_region_summary.md
    │   └── 商品、商家与地区结构阶段报告
    ├── customer_analysis_summary.md
    │   └── 客户购买行为与 RFM 分层阶段报告
    ├── delivery_analysis_summary.md
    │   └── 配送效率与用户评价阶段报告
    ├── statistical_analysis_summary.md
    │   └── 统计检验、回归及敏感性分析报告
    └── final_report.md
        └── 项目综合分析报告
```

## 五、主要结论

1. **订单增长不必然带来交易额同步增长。**&#8203;  
   主分析期共有 99,092 笔订单，其中 96,211 笔为有效已送达订单，商品 GMV 为 R$13,181,027.13，整体 AOV 为 R$137.00。2018 年 8 月有效订单环比增长 3.12%，但 AOV 下降 6.31%，商品 GMV 下降 3.38%。

2. **商品和地区交易存在一定集中，商家分布相对分散。**&#8203;  
   Top 5 品类贡献 39.88% GMV，Top 5 商家贡献 7.73%；买家侧 SP、RJ、MG 三州合计贡献 63.40%，商家侧 SP 单州贡献 64.39%。2018 年 8 月 AOV 的回落主要体现为平均商品明细金额下降，而非每单商品明细数量明显减少。

3. **样本交易主要由单次购买客户构成。**&#8203;  
   93,104 名购买客户中，2,789 名为样本内复购客户，占 3.00%。D、F 两类高消费单次客户合计占客户数 23.20%，贡献约 57.84% GMV，但该结构不能直接解释为未来客户终身价值或营销增量收益。

4. **配送延迟与低评分存在显著且较稳定的统计关联。**&#8203;  
   96,203 笔有效配送订单的平均配送时长为 12.54 天，延迟率为 6.79%；准时与延迟订单的低评分率分别为 9.24% 和 62.43%。控制买家州、订单商品金额和购买月份后，配送延迟的调整后 OR 为 14.81；调整低评分阈值和排除极端配送订单后，关联方向保持一致。

其中，GMV 指最终已送达订单的商品金额合计，不含运费，不等同于平台收入或利润；OR 表示优势比而非概率比。项目结论属于历史样本的描述性分析和统计关联研究，不构成因果证明。

## 六、阅读顺序

1. **综合报告：** 首先阅读 `reports/final_report.md`，了解完整研究背景、核心发现、统计结果、业务建议和分析边界。
2. **阶段报告：** 按经营表现、商品地区、客户价值、配送评价、统计分析的顺序，阅读 `reports/` 下对应的阶段报告。
3. **方法与口径：** 阅读 `docs/data_dictionary.md`、`docs/metrics_definition.md` 和 `docs/methodology.md`，核查字段含义、业务粒度、指标公式及异常处理方法。
4. **分析过程：** 按 `01` 至 `09` 的顺序查看 SQL，并结合 `notebooks/01` 至 `06` 了解数据检查、可视化和统计建模过程。
5. **结果核验：** 最后对照 `data/processed/` 中的分析数据和 `reports/figures/` 中的图表，检查报告结论与数据结果之间的对应关系。
