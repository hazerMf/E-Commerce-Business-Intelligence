-- 1. Create Dimension Tables First
CREATE TABLE dim_customer (
    customer_key VARCHAR(100) PRIMARY KEY,
    state VARCHAR(2),
    city VARCHAR(100)
);

CREATE TABLE dim_region (
    region_key INT PRIMARY KEY,
    city VARCHAR(100),
    state VARCHAR(2),
    latitude NUMERIC(10, 6),
    longitude NUMERIC(10, 6)
);

CREATE TABLE dim_item (
    item_key VARCHAR(100) PRIMARY KEY,
    category VARCHAR(100),
    weight INT,
    volume INT,
    name_length INT,
    description_length INT
);

CREATE TABLE dim_order_time (
    time_key INT PRIMARY KEY,
    full_date DATE,
    year INT,
    quarter VARCHAR(2),
    month_number INT,
    month_name VARCHAR(20),
    day_of_week VARCHAR(20)
);

-- 2. Create the Fact Table Last (so it can reference the Dimensions)
CREATE TABLE fact_order_item (
    sales_key SERIAL PRIMARY KEY, -- SERIAL automatically counts 1, 2, 3...
    order_id VARCHAR(100), -- The Degenerate Dimension
    item_key VARCHAR(100) REFERENCES dim_item(item_key),
    customer_key VARCHAR(100) REFERENCES dim_customer(customer_key),
    region_key INT REFERENCES dim_region(region_key),
    time_key INT REFERENCES dim_order_time(time_key),
    price NUMERIC(10, 2),
    freight_value NUMERIC(10, 2)
);