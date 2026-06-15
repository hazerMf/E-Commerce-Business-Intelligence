# E-Commerce Business Intelligence (BI) Project

A complete, end-to-end **Business Intelligence pipeline** built on the Brazilian **Olist e-commerce dataset**. This project covers every stage of a modern BI workflow — from raw data extraction, through star-schema transformation, to an interactive Metabase dashboard — all containerized with Docker.

---

## Dashboard Preview

![Metabase Dashboard](./dashboard.png)

---

## Table of Contents

- [Project Overview](#-project-overview)
- [Architecture](#-architecture)
- [Dataset](#-dataset)
- [Data Warehouse Schema (Star Schema)](#-data-warehouse-schema-star-schema)
- [ETL Pipeline](#-etl-pipeline)
- [Analytical Queries](#-analytical-queries)
- [Dashboard](#-dashboard)
- [Tech Stack](#-tech-stack)
- [Project Structure](#-project-structure)
- [Getting Started](#-getting-started)
- [Prerequisites](#prerequisites)
- [Setup & Run](#setup--run)

---

## Project Overview

This project answers key business questions for an e-commerce company using a fully automated data pipeline:

| # | Business Question |
|---|---|
| 1 | How does monthly revenue trend over time? |
| 2 | Where are customers located geographically? |
| 3 | What is the ratio of one-time vs. repeat customers? |
| 4 | Which are the top 10 products by revenue? |
| 5 | Which are the top 3 items within each top-selling category? |

---

## Architecture

```
Raw CSV Files (Olist Dataset)
        │
        ▼
┌──────────────────┐
│  ETL Pipeline    │  ← etl_pipeline.py (Python / Pandas)
│  Extract         │
│  Transform       │
│  Load            │
└────────┬─────────┘
         │
         ▼
┌──────────────────────────────────┐
│  PostgreSQL Data Warehouse       │  ← Docker container (bi_dw)
│  Star Schema                     │
│  • dim_customer                  │
│  • dim_region                    │
│  • dim_item                      │
│  • dim_order_time                │
│  • fact_order_item  (Fact Table) │
└────────┬─────────────────────────┘
         │
         ▼
┌──────────────────┐
│  Metabase        │  ← Docker container (port 3000)
│  Dashboard       │
└──────────────────┘
```

---

## Dataset

The raw data is sourced from the publicly available [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle). It represents ~100,000 orders placed between 2016 and 2018.

| File | Description |
|---|---|
| `olist_orders_dataset.csv` | Order-level data (status, timestamps) |
| `olist_order_items_dataset.csv` | Line-item data per order (product, price, freight) |
| `olist_customers_dataset.csv` | Customer info (ID, city, state, zip) |
| `olist_geolocation_dataset.csv` | Zip code–level lat/lon coordinates |
| `olist_products_dataset.csv` | Product metadata (category, weight, dimensions) |
| `olist_order_payments_dataset.csv` | Payment type and installment details |
| `olist_order_reviews_dataset.csv` | Customer review scores and comments |
| `olist_sellers_dataset.csv` | Seller info (city, state, zip) |
| `product_category_name_translation.csv` | Portuguese → English category name mapping |

> **Note:** All raw CSV files live in the `Raw_data/` directory and are excluded from version control via `.gitignore`.

---

## Data Warehouse Schema (Star Schema)

The data warehouse uses a **Star Schema** design for optimal query performance and analytical simplicity.

```
                        ┌───────────────────┐
                        │  dim_order_time   │
                        │─────────────────  │
                        │ PK: time_key      │
                        │ full_date         │
                        │ year              │
                        │ quarter           │
                        │ month_number      │
                        │ month_name        │
                        │ day_of_week       │
                        └────────┬──────────┘
                                 │
┌──────────────────┐    ┌────────┴──────────────┐    ┌──────────────────┐
│   dim_customer   │    │   fact_order_item     │    │    dim_item      │
│────────────────  │    │───────────────────    │    │────────────────  │
│ PK: customer_key │◄───│ PK: sales_key (SERIAL)│───►│ PK: item_key    │
│ state            │    │ order_id (deg. dim.)  │    │ category         │
│ city             │    │ FK: item_key          │    │ weight           │
└──────────────────┘    │ FK: customer_key      │    │ volume           │
                        │ FK: region_key        │    │ name_length      │
┌──────────────────┐    │ FK: time_key          │    │ description_len  │
│   dim_region     │    │ price                 │    └──────────────────┘
│────────────────  │    │ freight_value         │
│ PK: region_key   │◄───│                       │
│ city             │    └───────────────────────┘
│ state            │
│ latitude         │
│ longitude        │
└──────────────────┘
```

> `order_id` is kept in the fact table as a **degenerate dimension** — it carries analytical value (distinguishing orders) but has no separate dimension table.

---

## ETL Pipeline

The pipeline ([`etl_pipeline.py`](./etl_pipeline.py)) follows a classic **Extract → Transform → Load** pattern:

### 1. Extract
Reads all 6 relevant CSV files from `Raw_data/` into Pandas DataFrames.

### 2. Transform

| Dimension | Transformation Logic |
|---|---|
| `dim_customer` | Deduplicate on `customer_unique_id`; extract state & city |
| `dim_region` | Group by zip code prefix; average lat/lon; take first city/state |
| `dim_item` | Join products with English category translations; compute volume (L × H × W) |
| `dim_order_time` | Parse `order_purchase_timestamp`; extract year, quarter, month, day-of-week |
| `fact_order_item` | Join items ↔ orders ↔ customers; derive `time_key`; enforce referential integrity |

**Data Quality Step:** Before loading, foreign keys in the fact table are validated against all dimension tables to drop any orphaned records.

### 3. Load
Tables are loaded to PostgreSQL in dependency order:
1. All four dimension tables first (no FK dependencies)
2. `fact_order_item` last (depends on all four dimensions)

Uses `if_exists='append'` to safely add data without dropping existing tables.

---

## Analytical Queries

The file [`question.sql`](./question.sql) contains 5 production-ready analytical queries that power the Metabase dashboard:

```sql
-- 1. Monthly Revenue Trend
SELECT DATE_TRUNC('month', d.full_date) AS order_month, SUM(f.price) AS total_revenue
FROM fact_order_item f JOIN dim_order_time d ON f.time_key = d.time_key
GROUP BY 1 ORDER BY 1;

-- 2. Geographic Sales Density (Region Map)
SELECT r.latitude, r.longitude, r.state, COUNT(f.sales_key) AS total_items_sold
FROM fact_order_item f JOIN dim_region r ON f.region_key = r.region_key
GROUP BY 1, 2, 3;

-- 3. One-Time vs. Repeat Customers
WITH CustomerOrderCounts AS (
  SELECT customer_key, COUNT(DISTINCT order_id) AS total_orders
  FROM fact_order_item GROUP BY 1
)
SELECT CASE WHEN total_orders = 1 THEN 'One-Time Customer' ELSE 'Repeat Customer' END,
       COUNT(customer_key) FROM CustomerOrderCounts GROUP BY 1;

-- 4. Top 10 Products by Revenue
SELECT f.item_key, SUM(f.price) AS total_revenue, COUNT(f.sales_key) AS total_quantity_sold
FROM fact_order_item f JOIN dim_item d ON f.item_key = d.item_key
GROUP BY 1 ORDER BY 2 DESC LIMIT 10;

-- 5. Top 3 Items Within Each Top-Selling Category (Window Function)
-- Uses ROW_NUMBER() OVER (PARTITION BY category ORDER BY units_sold DESC)
```

---

## Dashboard

The Metabase dashboard (accessible at `http://localhost:3000`) contains **5 interactive visualizations**:

| Panel | Chart Type | Insight |
|---|---|---|
| **Monthly Revenue** | Line chart | Revenue grew from ~$200K/month (Jan 2017) to a peak of ~$1.1M/month (late 2017), with a sharp drop at the end of the dataset |
| **Region Map** | Geographic map | Sales are heavily concentrated in south-eastern Brazil (SP, RJ, MG states) |
| **Repeated vs One-Time Customers** | Donut chart | **96.95%** of 95,156 customers are one-time buyers; only **3.05%** return |
| **Top 10 Items by Revenue** | Combo bar chart | Dual-axis: total revenue vs. total quantity sold per product |
| **Top 3 Items in Top-Selling Categories** | Data table | Health & beauty leads in revenue ($1.25M), followed by watches/gifts ($1.19M) |

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Data Storage (Raw)** | CSV files (Olist public dataset) |
| **ETL / Transformation** | Python 3, Pandas 2.2.2 |
| **Database Connector** | SQLAlchemy 2.0.30, psycopg2-binary 2.9.9 |
| **Data Warehouse** | PostgreSQL 15 |
| **Visualization / BI** | Metabase (latest) |
| **Containerization** | Docker & Docker Compose |

---

## Project Structure

```
E-Commerce-Business-Intelligence/
│
├── Raw_data/                          # Raw CSV source files (not tracked in git)
│   ├── olist_orders_dataset.csv
│   ├── olist_order_items_dataset.csv
│   ├── olist_customers_dataset.csv
│   ├── olist_geolocation_dataset.csv
│   ├── olist_products_dataset.csv
│   ├── olist_order_payments_dataset.csv
│   ├── olist_order_reviews_dataset.csv
│   ├── olist_sellers_dataset.csv
│   └── product_category_name_translation.csv
│
├── Report/
│   └── Report.docx                    # Full written project report
│
├── etl_pipeline.py                    # Main ETL script (Extract, Transform, Load)
├── init.sql                           # PostgreSQL DDL — creates all tables
├── question.sql                       # 5 analytical SQL queries for the dashboard
├── docker-compose.yml                 # Spins up PostgreSQL + Metabase
├── requirements.txt                   # Python dependencies
├── dashboard.png                      # Screenshot of the final Metabase dashboard
├── Bài tập lớn Business Intelligence.docx  # Original assignment brief (Vietnamese)
└── README.md
```

---

## Getting Started

### Prerequisites

Make sure you have the following installed:

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (includes Docker Compose)
- [Python 3.10+](https://www.python.org/downloads/)
- The Olist raw CSV files placed inside the `Raw_data/` directory

### Setup & Run

#### Step 1 — Clone the repository
```bash
git clone <your-repo-url>
cd E-Commerce-Business-Intelligence
```

#### Step 2 — Download the raw data
Download the Olist dataset from [Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) and place all CSV files into the `Raw_data/` directory.

#### Step 3 — Start the Docker services
This command launches both **PostgreSQL** and **Metabase**:
```bash
docker-compose up -d
```

Wait ~30 seconds for the containers to fully initialize.

#### Step 4 — Initialize the database schema
Connect to the PostgreSQL container and run the DDL script:
```bash
docker exec -i bi_dw psql -U admin -d ecom_dw < init.sql
```

#### Step 5 — Install Python dependencies
```bash
pip install -r requirements.txt
```

#### Step 6 — Run the ETL pipeline
```bash
python etl_pipeline.py
```

Expected output:
```
Starting ETL Pipeline
Extracting data from CSVs...
Transforming data into Star Schema...
Loading data into PostgreSQL...
   ✅ dim_customer loaded.
   ✅ dim_region loaded.
   ✅ dim_item loaded.
   ✅ dim_order_time loaded.
   ✅ fact_order_item loaded.
ETL Pipeline Complete!
```

#### Step 7 — Open Metabase and connect the database
1. Navigate to **http://localhost:3000** in your browser
2. Complete the Metabase onboarding wizard
3. When prompted to add a database, use these settings:
   - **Type:** PostgreSQL
   - **Host:** `postgres` (the Docker service name)
   - **Port:** `5432`
   - **Database name:** `ecom_dw`
   - **Username:** `admin`
   - **Password:** `admin`
4. Create a new dashboard and add questions using the queries in [`question.sql`](./question.sql)

---

## Default Credentials

| Service | URL | Username | Password |
|---|---|---|---|
| PostgreSQL | `localhost:5432` | `admin` | `admin` |
| Metabase | `http://localhost:3000` | *(set during setup)* | *(set during setup)* |

---

##  License

This project uses the [Olist public dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) which is licensed under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/). This project is intended for educational purposes.