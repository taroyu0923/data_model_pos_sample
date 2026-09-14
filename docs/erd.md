# The Daily Grind — Data Model (Task 1)

Source of decisions: [project_plan.md](project_plan.md).

## 1. Conceptual model

Business entities and how they relate. A Sale is recorded as an Order made of Order Items.

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    STORE ||--o{ ORDER : records
    ORDER ||--|{ ORDER_ITEM : contains
    PRODUCT ||--o{ ORDER_ITEM : "appears in"
```

- A **Customer** places zero or more Orders. An Order has at most one identified customer; walk-ins are *Guest*, unreadable contacts are *Unknown*.
- A **Store** records zero or more Orders; every Order belongs to exactly one Store.
- An **Order** contains one or more **Order Items**. A return is an Order Item with negative quantity.
- A **Product** appears in zero or more Order Items (e.g. `UNKNOWN_ITEM` has never sold).

## 2. Logical model (normalised, 3NF)

Attributes and keys, independent of database. Fixes the source's 1NF breaks: the delimited `items_sold` string becomes `ORDER_ITEM` rows, and the `store_metadata` JSON becomes `STORE`.

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    STORE ||--o{ ORDER : records
    ORDER ||--|{ ORDER_ITEM : contains
    PRODUCT ||--o{ ORDER_ITEM : "appears in"

    CUSTOMER {
        string customer_email PK
        string full_name
        string tier
        datetime updated_at
    }
    STORE {
        string store_id PK
        string city
        string region
    }
    PRODUCT {
        string item_code PK
        string category
        string sub_category
        decimal unit_price
    }
    ORDER {
        string tx_id PK
        datetime sale_timestamp
        string customer_email FK
        string store_id FK
    }
    ORDER_ITEM {
        string tx_id PK, FK
        string item_code PK, FK
        int quantity
    }
```

## 3. Physical model — Kimball star schema (DuckDB, Gold layer)

Two facts at different grains share conformed dimensions.
`fct_orders` = one row per transaction; `fct_order_items` = one row per item per transaction.
`DECIMAL` precision is in the comment (Mermaid types cannot contain commas).

```mermaid
erDiagram
    dim_customer ||--o{ fct_orders : "customer_id"
    dim_store ||--o{ fct_orders : "store_id"
    dim_date ||--o{ fct_orders : "date_day"
    fct_orders ||--|{ fct_order_items : "tx_id"
    dim_item ||--o{ fct_order_items : "item_code"
    dim_customer ||--o{ fct_order_items : "customer_id"
    dim_store ||--o{ fct_order_items : "store_id"
    dim_date ||--o{ fct_order_items : "date_day"

    dim_customer {
        VARCHAR customer_id PK "lower-case email or __guest__ / __unknown__"
        VARCHAR cust_email "null for guest / unknown"
        VARCHAR full_name "Title Case"
        VARCHAR tier "Gold, Silver, None"
        TIMESTAMP updated_at "latest record; first purchase if inferred"
        VARCHAR customer_type "member, inferred, guest, unknown"
    }
    dim_item {
        VARCHAR item_code PK
        VARCHAR item_category "e.g. Beverage"
        VARCHAR item_category_sub "e.g. Latte"
        DECIMAL unit_price "10,2 USD"
    }
    dim_store {
        VARCHAR store_id PK
        VARCHAR city
        VARCHAR region
    }
    dim_date {
        DATE date_day PK
        INTEGER year
        INTEGER month
        VARCHAR month_name
        DATE week_start_date "Monday"
        INTEGER day_of_week "ISO 1 = Mon"
        VARCHAR day_name
        BOOLEAN is_weekend
    }
    fct_orders {
        VARCHAR tx_id PK
        TIMESTAMP sale_timestamp
        DATE date_day FK
        VARCHAR customer_id FK
        VARCHAR store_id FK
        INTEGER line_count
        INTEGER unit_count "signed"
        DECIMAL order_revenue "10,2 signed"
        BOOLEAN is_return_order "all lines are returns"
    }
    fct_order_items {
        VARCHAR tx_id PK, FK
        VARCHAR item_code PK, FK
        TIMESTAMP sale_timestamp
        DATE date_day FK
        VARCHAR customer_id FK
        VARCHAR store_id FK
        INTEGER quantity "signed, -1 = return"
        BOOLEAN is_return
        DECIMAL unit_price "10,2 from catalog"
        DECIMAL line_revenue "10,2 quantity x unit_price"
        DECIMAL order_fraction "10,4 = 1 / line_count"
    }
```

## 4. Design choices

| Choice | Why |
|---|---|
| Two facts (order + order item) | Order KPIs (orders, AOV) need one row per transaction; product performance needs line grain. Keeping both avoids double-counting orders when slicing by product. |
| `order_fraction` on line fact | Σ `order_fraction` per product = orders attributed to that product without double counting (split by line). |
| Signed `quantity` + `is_return` | Revenue sums are correct without filters; the flag still lets managers see returns separately. |
| `is_return_order` | Return-only transactions are excluded from order count and AOV but still reduce net revenue. |
| Dimension keys repeated on line fact | Power BI can filter product visuals by store, date and customer directly (star, not snowflake). |
| Latest record only in `dim_customer` | Brief says "we only want the latest"; history stays in Silver. |
| Guest / Unknown / inferred customers | Every sale joins to a customer, so no revenue disappears from joined visuals. |
| `unit_price` stored on the fact | Protects past revenue from future catalog price changes. |
| `dim_date` | Enables trend visuals and time intelligence in Power BI. |
