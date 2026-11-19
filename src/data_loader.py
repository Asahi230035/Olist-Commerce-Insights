from pathlib import Path
from getpass import getpass

import pandas as pd
from sqlalchemy import create_engine, text, inspect
from sqlalchemy.engine import URL


# ==============================
# 1. 项目配置
# ==============================

PROJECT_ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = PROJECT_ROOT / "data" / "raw"

DB_NAME = "olist_analysis"

# 按外键依赖顺序导入
TABLE_CONFIG = [
    ("customers", "olist_customers_dataset.csv"),
    ("category_translation", "product_category_name_translation.csv"),
    ("products", "olist_products_dataset.csv"),
    ("sellers", "olist_sellers_dataset.csv"),
    ("orders", "olist_orders_dataset.csv"),
    ("order_items", "olist_order_items_dataset.csv"),
    ("order_payments", "olist_order_payments_dataset.csv"),
    ("order_reviews", "olist_order_reviews_dataset.csv"),
    ("geolocation", "olist_geolocation_dataset.csv"),
]

# 保留邮编前导零
ZIP_COLUMNS = {
    "customers": "customer_zip_code_prefix",
    "sellers": "seller_zip_code_prefix",
    "geolocation": "geolocation_zip_code_prefix",
}

# 时间字段
DATE_COLUMNS = {
    "orders": [
        "order_purchase_timestamp",
        "order_approved_at",
        "order_delivered_carrier_date",
        "order_delivered_customer_date",
        "order_estimated_delivery_date",
    ],
    "order_items": [
        "shipping_limit_date",
    ],
    "order_reviews": [
        "review_creation_date",
        "review_answer_timestamp",
    ],
}


# ==============================
# 2. 创建数据库连接
# ==============================

password = getpass("请输入 MySQL root 密码：")

url = URL.create(
    drivername="mysql+pymysql",
    username="root",
    password=password,
    host="127.0.0.1",
    port=3306,
    database=DB_NAME,
)

engine = create_engine(url, pool_pre_ping=True)


# ==============================
# 3. 检查数据库状态
# ==============================

table_names = [name for name, _ in TABLE_CONFIG]

inspector = inspect(engine)

for table in table_names:
    if not inspector.has_table(table):
        raise RuntimeError(f"数据库缺少表：{table}")

# 避免重复导入或覆盖已有数据
with engine.connect() as conn:
    for table in table_names:
        count = conn.execute(
            text(f"SELECT COUNT(*) FROM `{table}`")
        ).scalar_one()

        if count != 0:
            raise RuntimeError(
                f"{table} 已有 {count} 条数据，请勿重复导入"
            )


# ==============================
# 4. 分批导入 CSV
# ==============================

for table, filename in TABLE_CONFIG:

    file_path = DATA_DIR / filename

    if not file_path.exists():
        raise FileNotFoundError(file_path)

    print(f"\n开始导入：{table}")

    dtype_config = {}

    if table in ZIP_COLUMNS:
        dtype_config[ZIP_COLUMNS[table]] = "string"

    total_rows = 0

    # 每张表单独使用一个数据库事务
    with engine.begin() as conn:

        chunks = pd.read_csv(
            file_path,
            chunksize=5000,
            dtype=dtype_config,
        )

        for chunk in chunks:

            # 转换时间字段，并检查转换失败的记录
            for col in DATE_COLUMNS.get(table, []):

                original = chunk[col]

                converted = pd.to_datetime(
                    original,
                    errors="coerce"
                )

                invalid = original.notna() & converted.isna()

                if invalid.any():
                    raise ValueError(
                        f"{table}.{col} 存在 "
                        f"{invalid.sum()} 个无法解析的时间值"
                    )

                chunk[col] = converted

            # 写入 MySQL
            chunk.to_sql(
                name=table,
                con=conn,
                if_exists="append",
                index=False,
                chunksize=1000,
                method="multi",
            )

            total_rows += len(chunk)

    # 验证写入数量
    with engine.connect() as conn:
        db_count = conn.execute(
            text(f"SELECT COUNT(*) FROM `{table}`")
        ).scalar_one()

    if db_count != total_rows:
        raise RuntimeError(
            f"{table} 数据量不一致："
            f"CSV={total_rows}, MySQL={db_count}"
        )

    print(f"导入完成：{table}，共 {db_count} 行")


engine.dispose()

print("\n全部数据导入成功！")