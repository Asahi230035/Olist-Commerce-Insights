-- ==========================================
-- Olist 电商数据分析项目
-- 数据库及原始数据表创建
-- ==========================================

CREATE DATABASE IF NOT EXISTS olist_analysis
CHARACTER SET utf8mb4
COLLATE utf8mb4_unicode_ci;

USE olist_analysis;


-- 1. 客户表
CREATE TABLE customers (
    customer_id VARCHAR(32) PRIMARY KEY,
    customer_unique_id VARCHAR(32) NOT NULL,
    customer_zip_code_prefix VARCHAR(5),
    customer_city VARCHAR(120),
    customer_state CHAR(2),

    INDEX idx_customer_unique_id (customer_unique_id)
);


-- 2. 商品类别翻译表
CREATE TABLE category_translation (
    product_category_name VARCHAR(150) PRIMARY KEY,
    product_category_name_english VARCHAR(150)
);


-- 3. 商品表
CREATE TABLE products (
    product_id VARCHAR(32) PRIMARY KEY,
    product_category_name VARCHAR(150),
    product_name_lenght INT,
    product_description_lenght INT,
    product_photos_qty INT,
    product_weight_g INT,
    product_length_cm INT,
    product_height_cm INT,
    product_width_cm INT,

    INDEX idx_product_category (product_category_name)
);


-- 4. 商家表
CREATE TABLE sellers (
    seller_id VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(5),
    seller_city VARCHAR(120),
    seller_state CHAR(2)
);


-- 5. 订单表
CREATE TABLE orders (
    order_id VARCHAR(32) PRIMARY KEY,
    customer_id VARCHAR(32) NOT NULL,
    order_status VARCHAR(20),

    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME,

    FOREIGN KEY (customer_id)
        REFERENCES customers(customer_id),

    INDEX idx_order_purchase (order_purchase_timestamp),
    INDEX idx_order_status (order_status)
);


-- 6. 订单商品明细表
CREATE TABLE order_items (
    order_id VARCHAR(32),
    order_item_id INT,
    product_id VARCHAR(32),
    seller_id VARCHAR(32),

    shipping_limit_date DATETIME,
    price DECIMAL(12,2),
    freight_value DECIMAL(12,2),

    PRIMARY KEY (order_id, order_item_id),

    FOREIGN KEY (order_id)
        REFERENCES orders(order_id),

    FOREIGN KEY (product_id)
        REFERENCES products(product_id),

    FOREIGN KEY (seller_id)
        REFERENCES sellers(seller_id)
);


-- 7. 订单支付表
CREATE TABLE order_payments (
    order_id VARCHAR(32),
    payment_sequential INT,
    payment_type VARCHAR(30),
    payment_installments INT,
    payment_value DECIMAL(12,2),

    PRIMARY KEY (order_id, payment_sequential),

    FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
);


-- 8. 订单评价表
CREATE TABLE order_reviews (
    review_id VARCHAR(32),
    order_id VARCHAR(32),

    review_score INT,
    review_comment_title TEXT,
    review_comment_message TEXT,
    review_creation_date DATETIME,
    review_answer_timestamp DATETIME,

    PRIMARY KEY (review_id, order_id),

    FOREIGN KEY (order_id)
        REFERENCES orders(order_id)
);


-- 9. 地理位置表
CREATE TABLE geolocation (
    geo_id BIGINT AUTO_INCREMENT PRIMARY KEY,
    geolocation_zip_code_prefix VARCHAR(5),
    geolocation_lat DOUBLE,
    geolocation_lng DOUBLE,
    geolocation_city VARCHAR(120),
    geolocation_state CHAR(2),

    INDEX idx_geo_zip (geolocation_zip_code_prefix)
);