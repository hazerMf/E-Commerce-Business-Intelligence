-- 1. Monthly Rev

SELECT 
    DATE_TRUNC('month', d.full_date) AS order_month,
    SUM(f.price) AS total_revenue
FROM 
    fact_order_item f
JOIN 
    dim_order_time d ON f.time_key = d.time_key
GROUP BY 
    DATE_TRUNC('month', d.full_date)
ORDER BY 
    order_month ASC;

-- 2. Region map

SELECT 
    r.latitude, 
    r.longitude, 
    r.state,
    COUNT(f.sales_key) AS total_items_sold
FROM 
    fact_order_item f
JOIN 
    dim_region r ON f.region_key = r.region_key
GROUP BY 
    r.latitude, r.longitude, r.state;

-- 3. Repeated vs One-time cus

WITH CustomerOrderCounts AS (
    SELECT 
        customer_key, 
        COUNT(DISTINCT order_id) AS total_orders
    FROM 
        fact_order_item
    GROUP BY 
        customer_key
)
SELECT 
    CASE 
        WHEN total_orders = 1 THEN 'One-Time Customer' 
        ELSE 'Repeat Customer' 
    END AS customer_type,
    COUNT(customer_key) AS total_customers
FROM 
    CustomerOrderCounts
GROUP BY 
    CASE 
        WHEN total_orders = 1 THEN 'One-Time Customer' 
        ELSE 'Repeat Customer' 
    END;

-- 4. Top 10 item by rev

SELECT 
    f.item_key AS product_id,
    SUM(f.price) AS total_revenue,
    COUNT(f.sales_key) AS total_quantity_sold
FROM 
    fact_order_item f
JOIN 
    dim_item d ON f.item_key = d.item_key
GROUP BY 
    f.item_key
ORDER BY 
    total_revenue DESC
LIMIT 10;

-- 5. Top 3 item in top sale cate

WITH ranked_items AS (
    SELECT 
        i.category,
        f.item_key,
        COUNT(f.sales_key) AS units_sold,
        SUM(f.price) AS item_revenue,
        ROW_NUMBER() OVER (
            PARTITION BY i.category 
            ORDER BY COUNT(f.sales_key) DESC
        ) AS item_rank
    FROM fact_order_item f
    JOIN dim_item i ON f.item_key = i.item_key
    GROUP BY i.category, f.item_key
),
category_totals AS (
    SELECT 
        category,
        SUM(units_sold) AS total_category_volume,
        SUM(item_revenue) AS total_category_revenue
    FROM ranked_items
    GROUP BY category
)
SELECT 
    ct.category,
    ct.total_category_volume,
    ct.total_category_revenue,
    ri.item_key AS top_performing_item,
    ri.units_sold AS item_units_sold,
    ri.item_rank
FROM category_totals ct
JOIN ranked_items ri ON ct.category = ri.category
WHERE ri.item_rank <= 3 -- Change this number to show more or fewer items per category
ORDER BY ct.total_category_revenue DESC, ri.item_rank;