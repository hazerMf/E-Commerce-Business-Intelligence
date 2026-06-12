import pandas as pd
from sqlalchemy import create_engine

# ==========================================
# 0. SETUP & CONNECTION
# ==========================================
print("Starting ETL Pipeline")
db_string = "postgresql://admin:admin@localhost:5432/ecom_dw"
engine = create_engine(db_string)
data_dir = './Raw_data/'

# ==========================================
# 1. EXTRACT
# ==========================================
print("Extracting data from CSVs...")
df_orders = pd.read_csv(data_dir + 'olist_orders_dataset.csv')
df_items = pd.read_csv(data_dir + 'olist_order_items_dataset.csv')
df_products = pd.read_csv(data_dir + 'olist_products_dataset.csv')
df_translations = pd.read_csv(data_dir + 'product_category_name_translation.csv')
df_customers = pd.read_csv(data_dir + 'olist_customers_dataset.csv')
df_geo = pd.read_csv(data_dir + 'olist_geolocation_dataset.csv')

# ==========================================
# 2. TRANSFORM
# ==========================================
print("Transforming data into Star Schema...")

# --- A. Transform: Dim Customer ---
# Deduplicate to get unique humans, rename to match DB columns
dim_customer = df_customers.drop_duplicates(subset=['customer_unique_id']).copy()
dim_customer = dim_customer[['customer_unique_id', 'customer_state', 'customer_city']]
dim_customer.columns = ['customer_key', 'state', 'city']

# --- B. Transform: Dim Region ---
# Group by zip code, average the lat/long, take the first city/state
dim_region = df_geo.groupby('geolocation_zip_code_prefix').agg({
    'geolocation_city': 'first',
    'geolocation_state': 'first',
    'geolocation_lat': 'mean',
    'geolocation_lng': 'mean'
}).reset_index()
dim_region.columns = ['region_key', 'city', 'state', 'latitude', 'longitude']

# --- C. Transform: Dim Item ---
# Join translations, calculate volume, rename columns
dim_item = pd.merge(df_products, df_translations, on='product_category_name', how='left')
dim_item['volume'] = dim_item['product_length_cm'] * dim_item['product_height_cm'] * dim_item['product_width_cm']
dim_item = dim_item[['product_id', 'product_category_name_english', 'product_weight_g', 
                     'volume', 'product_name_lenght', 'product_description_lenght']]
dim_item.columns = ['item_key', 'category', 'weight', 'volume', 'name_length', 'description_length']

# --- D. Transform: Dim Order Time ---
# Convert timestamp, extract date parts
df_orders['order_purchase_timestamp'] = pd.to_datetime(df_orders['order_purchase_timestamp'])
# Create a unique dataframe of just the dates
dim_order_time = pd.DataFrame({'full_date': df_orders['order_purchase_timestamp'].dt.date}).drop_duplicates()
dim_order_time['full_date'] = pd.to_datetime(dim_order_time['full_date'])

dim_order_time['time_key'] = dim_order_time['full_date'].dt.strftime('%Y%m%d').astype(int)
dim_order_time['year'] = dim_order_time['full_date'].dt.year
dim_order_time['quarter'] = 'Q' + dim_order_time['full_date'].dt.quarter.astype(str)
dim_order_time['month_number'] = dim_order_time['full_date'].dt.month
dim_order_time['month_name'] = dim_order_time['full_date'].dt.month_name()
dim_order_time['day_of_week'] = dim_order_time['full_date'].dt.day_name()

# Reorder columns to match DB
dim_order_time = dim_order_time[['time_key', 'full_date', 'year', 'quarter', 'month_number', 'month_name', 'day_of_week']]

# --- E. Transform: Fact Order Item ---
# Merge items with orders to get timestamps and customer_id
fact = pd.merge(df_items, df_orders[['order_id', 'customer_id', 'order_purchase_timestamp']], on='order_id', how='left')
# Merge with customers to get unique_id and zip_code
fact = pd.merge(fact, df_customers[['customer_id', 'customer_unique_id', 'customer_zip_code_prefix']], on='customer_id', how='left')

# Generate the Time Key for the Fact table
fact['time_key'] = pd.to_datetime(fact['order_purchase_timestamp']).dt.strftime('%Y%m%d').astype(int)

# Select and rename final columns
fact = fact[['order_id', 'product_id', 'customer_unique_id', 'customer_zip_code_prefix', 'time_key', 'price', 'freight_value']]
fact.columns = ['order_id', 'item_key', 'customer_key', 'region_key', 'time_key', 'price', 'freight_value']

# Drop any facts that somehow have missing dimensions (Data Quality Check)
fact = fact.dropna(subset=['item_key', 'customer_key', 'region_key', 'time_key'])

# Drop any facts that somehow have missing dimensions (Data Quality Check)
fact = fact.dropna(subset=['item_key', 'customer_key', 'region_key', 'time_key'])

# NEW FIX: Ensure all foreign keys actually exist in our Dimension tables!
fact = fact[fact['region_key'].isin(dim_region['region_key'])]
fact = fact[fact['item_key'].isin(dim_item['item_key'])]
fact = fact[fact['customer_key'].isin(dim_customer['customer_key'])]

# ==========================================
# 3. LOAD
# ==========================================
print("Loading data into PostgreSQL...")

# Load Dimensions First (because of Foreign Key constraints)
dim_customer.to_sql('dim_customer', engine, if_exists='append', index=False)
print("   ✅ dim_customer loaded.")

dim_region.to_sql('dim_region', engine, if_exists='append', index=False)
print("   ✅ dim_region loaded.")

dim_item.to_sql('dim_item', engine, if_exists='append', index=False)
print("   ✅ dim_item loaded.")

dim_order_time.to_sql('dim_order_time', engine, if_exists='append', index=False)
print("   ✅ dim_order_time loaded.")

# Load Fact Table Last
fact.to_sql('fact_order_item', engine, if_exists='append', index=False)
print("   ✅ fact_order_item loaded.")

print("ETL Pipeline Complete!")