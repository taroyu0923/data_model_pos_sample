# Store Manager Dashboard — User Guide

How to use The Daily Grind Power BI dashboard, and what every metric means. The dashboard reads the Gold tables exported to `exports/*.parquet` (see [README](../README.md)).

> **Demo data:** the current files hold 8 transactions over 4 days (1–4 Aug 2026). Trends are illustrative only.

## What the dashboard is for

It shows how the stores are selling: revenue, orders, what customers buy, and who the customers are. Use it for a quick daily check and to compare stores, products and customer groups.

## How to use it

1. **Filter with the slicers at the top.** They appear on every page and stay in sync between pages.

   | Slicer | What it does |
   |---|---|
   | Date | Drag the handles to choose a date range. |
   | Store | Choose one or more stores; clear it to see all stores. |
   | Customer type | Show only members, guests, and so on. |

2. **Click a chart to filter the page.** Clicking a bar (for example one store) filters the other visuals on that page. Click it again, or an empty area, to clear.
3. **Hover for details.** Hovering over a bar or point shows its exact values.
4. **Move between pages** with the page tabs at the bottom or the buttons on the Overview page.
5. **Reset.** If numbers look unexpectedly small, a slicer or click-filter is probably still on. Clear slicers with their eraser icon.

## Metric definitions

These metrics mean the same on every page.

| Metric | Definition | Notes |
|---|---|---|
| Net Revenue | Sales value minus returns, USD. | Can be negative for a period with only returns. |
| Orders | Number of purchase transactions. | A transaction where **every** item is a return is not counted. |
| AOV (Average Order Value) | Revenue of purchase orders ÷ Orders. | Excludes return-only transactions, so AOV can be higher than Net Revenue on a day with returns. |
| Units Sold | Items sold. | Returns are not subtracted. |
| Units Returned | Items returned, shown as a positive number. | See [Known limitations](#known-limitations). |
| Return Value | Value of returned items, USD. | Already subtracted in Net Revenue. |
| Line Revenue | Net revenue calculated per product line. | Used for product and category views; equals Net Revenue when no product filter is applied. |
| Fractional Orders | Each order is shared equally between the products in it (2 products → 0.5 each). | Product and category order counts add up exactly to Orders. |
| Revenue Share % | A product's Line Revenue as a share of total Line Revenue in the current filters. | |

### Customer terms

| Term | Meaning |
|---|---|
| Tier | Loyalty level: **Gold**, **Silver** or **None**. |
| Member | Customer registered in the loyalty programme. A member can still have tier None. |
| Inferred | Gave a valid email at checkout but is not in the loyalty programme. Tier None. |
| Guest | Gave no contact details. Tier None. |
| Unknown | Contact details could not be read (for example an invalid email). Tier None. |

Tier **None** therefore mixes members without a tier with inferred, guest and unknown customers. Use Customer type to separate them.

## Page 1 — Overview

**Question:** How are we doing overall?

| Visual | Shows | How to read it |
|---|---|---|
| KPI cards | Net Revenue, Orders, AOV, Units Sold, Units Returned | Headline numbers for the current filters. Start here. |
| Revenue by store (bar) | Net Revenue per store, highest first | Best and weakest stores at a glance. |
| Daily revenue (columns) | Net Revenue per day | Good and slow days. |
| Navigation buttons | Links to pages 2–5 | Click to go deeper. |

**Tip:** check Units Returned. A high value means revenue is lost to returns, not to low sales.

## Page 2 — Category & Items

**Question:** What sells?

| Visual | Shows | How to read it |
|---|---|---|
| Category slicer | Beverage, Food, Merch, Unknown | Narrows this page only. |
| Revenue by category (bar) | Line Revenue per category | Which category earns most. |
| Orders by category (donut) | Fractional Orders per category | Share of orders; slices add up to total Orders. |
| Item table | Units Sold, Units Returned, Line Revenue, Revenue Share %, Fractional Orders per item | Sorted by revenue; data bars show relative size. |
| Top 5 items (bar) | Five items with the most units sold | Best sellers, for stock and promotions. |

**Notes:**

- A category with a large share of orders but a small share of revenue usually sells low-priced items.
- **Unknown** category = an item sold at the till but missing from the product catalogue. It shows $0 revenue; report it so the catalogue can be fixed.

## Page 3 — Stores

**Question:** How does each store perform?

| Visual | Shows | How to read it |
|---|---|---|
| KPI cards | Net Revenue, Orders, AOV | Update when you click a store. |
| Revenue by store (bar) | Net Revenue per store | Click a store to filter the page. |
| Orders & AOV by store (columns + line) | Orders as columns, AOV as a line | Many orders + low AOV = many small baskets; few orders + high AOV = fewer, larger purchases. |
| Store × category heatmap (matrix) | Line Revenue per store and category | Darker = more revenue. Shows each store's strengths and gaps. |

**Tip:** if one store sells far more of a category, look at what it does differently.

## Page 4 — Daily

**Question:** What happened each day?

| Visual | Shows | How to read it |
|---|---|---|
| Revenue & Orders by day (columns + line) | Net Revenue columns, Orders line on its own axis | Compare revenue with order count. |
| Revenue by day and store (stacked columns) | Each day's revenue split by store | Which store drove each day. A section **below zero** means that store had more returns than sales that day. |
| Daily table | Orders, Net Revenue, AOV, Units Sold, Units Returned per day | Exact figures with totals. |

**Example — AOV above Net Revenue:** on 2 Aug, Seattle's order TX-1004 was $16.75 and Portland's TX-1005 was a return-only transaction of −$3.50. Net Revenue is $13.25, but Orders is 1 and AOV is $16.75, because the return is subtracted from revenue but is not an order.

## Page 5 — Customers

**Question:** Who are our customers, and do loyalty members spend more?

| Visual | Shows | How to read it |
|---|---|---|
| Revenue by tier (columns) | Net Revenue for Gold, Silver, None | Revenue from each loyalty level. |
| AOV by tier (columns) | Average order value per tier | Whether higher tiers spend more per visit. |
| Orders by customer type (donut) | Orders from member, inferred, guest, unknown | Loyalty business vs everyone else. |
| Tier breakdown (matrix) | Orders, Net Revenue, AOV by tier; click **+** to expand into customer type | Splits tier None into its customer types. |
| Top 5 customers (table) | Highest-spending identifiable customers | Guests and unknown customers excluded. |

**Tip:** inferred customers gave an email but have not joined the loyalty programme — easy sign-up targets.

## Known limitations

- **Demo data:** 8 transactions over 4 days.
- **Current prices:** revenue uses today's catalogue prices; past sales at a different price are misstated.
- **Hidden returns:** a sale and a return of the same item in one transaction cancel into one line, so that return is not counted in Units Returned.
- **Time zone:** timestamps have no time zone; all stores are treated as local (Pacific) time.
