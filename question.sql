-- 1. Avg order value

SELECT SUM(price) / COUNT(DISTINCT order_id) AS "AOV"
FROM fact_order_item;

-- 2. Monthly revenue

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

-- 3. Region map

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

-- 4. Repeated vs One-time Customer

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

-- 5. Top 10 item category

SELECT 
    i.category AS product_category,
    SUM(f.price) AS total_revenue
FROM fact_order_item f
JOIN dim_item i ON f.item_key = i.item_key
WHERE i.category IS NOT NULL
GROUP BY i.category
ORDER BY total_revenue DESC
LIMIT 10;

-- 6. Total order

SELECT COUNT(DISTINCT order_id) AS "Total Orders"
FROM fact_order_item;

-- 7. Total revenue

SELECT SUM(price) AS "Total Revenue"
FROM fact_order_item;

-- 8. Weekday sales revenue and number

SELECT 
    t.day_of_week,
    COUNT(DISTINCT f.order_id) AS total_orders,
    SUM(f.price) AS total_revenue
FROM fact_order_item f
JOIN dim_order_time t ON f.time_key = t.time_key
GROUP BY t.day_of_week
ORDER BY 
    -- This ensures the days are sorted logically rather than alphabetically
    CASE t.day_of_week
        WHEN 'Monday' THEN 1
        WHEN 'Tuesday' THEN 2
        WHEN 'Wednesday' THEN 3
        WHEN 'Thursday' THEN 4
        WHEN 'Friday' THEN 5
        WHEN 'Saturday' THEN 6
        WHEN 'Sunday' THEN 7
    END;

-- 9. Revenue by state

SELECT
    c.state,
    COUNT(DISTINCT f.customer_key) AS total_unique_customers,
    SUM(f.price) AS total_revenue
FROM
    fact_order_item f
JOIN
    dim_customer c ON f.customer_key = c.customer_key
GROUP BY
    c.state
ORDER BY
    total_revenue DESC;

