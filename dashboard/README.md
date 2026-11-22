# Real-Time Semantic Intelligence Dashboard (Method 2)

An interactive, multi-tab executive and operational web dashboard built in Python (Streamlit + Plotly) that connects directly to Azure Databricks Unity Catalog (`gold_catalog.semantic_reporting`).

Whenever your Azure Data Factory pipeline or Databricks serverless workflows update the Gold and Semantic layers, this dashboard automatically queries the fresh Delta Lake snapshot!

---

## 🚀 Quickstart (1-Click on Windows)

1. Navigate to the `dashboard/` directory.
2. Double-click **`run_dashboard.bat`** (or execute in PowerShell: `.\run_dashboard.bat`).
3. Your default web browser will open at:
   👉 **`http://localhost:8501`**

---

## ⚙️ Connecting to Live Databricks SQL (Real-Time Mode)

You can connect in either of two ways:

### Option A: Enter Connection in the Web Sidebar (Fastest)
1. Open the dashboard in your browser (`http://localhost:8501`).
2. In the left sidebar:
   - Select **Live Databricks SQL**.
   - Paste your **SQL Warehouse HTTP Path** (see below).
   - Paste your **Databricks Token** (PAT).
3. The dashboard will instantly switch to **`🟢 LIVE DATABRICKS CONNECTED`** and pull real-time data!

### Option B: Save in `.env` File
1. Copy `.env.example` to `.env`:
   ```powershell
   cp .env.example .env
   ```
2. Fill in your details:
   ```env
   DATABRICKS_SERVER_HOSTNAME=adb-7405612959366844.4.azuredatabricks.net
   DATABRICKS_HTTP_PATH=/sql/1.0/warehouses/<YOUR_SQL_WAREHOUSE_ID>
   DATABRICKS_ACCESS_TOKEN=dapi...
   ```
   *(Note: `.env` is excluded in `.gitignore` so your credentials are never committed to Git).*

---

## 🔍 How to Find Your Databricks SQL Warehouse HTTP Path:
1. Open your Azure Databricks workspace: `https://adb-7405612959366844.4.azuredatabricks.net`.
2. In the left navigation menu, click **SQL Warehouses** (or **Compute** $\rightarrow$ **SQL Warehouses**).
3. Click on your active SQL Warehouse (e.g. `Serverless Starter Warehouse`).
4. Click the **Connection details** tab.
5. Copy the **HTTP Path** (looks like `/sql/1.0/warehouses/1234567890abcdef`).

---

## 📑 Dashboard Features

1. **📊 Executive Command Center (`vw_executive_kpi_dashboard`)**:
   - Real-time Gross Written Premium, Overall Loss Ratio %, and Active Policy count.
   - Monthly trend comparison: Premium Written vs. Incurred Losses.
   - Portfolio Underwriting Health breakdown (Profitable vs. Critical).
2. **🏆 Agent Sales & Producer Leaderboard (`vw_agent_leaderboard`)**:
   - Real-time rankings of top producers by premium volume.
   - Interactive horizontal bar chart colored by Agent Loss Ratio %.
   - Producer tiers (💎 Platinum, 🥇 Gold, 🥈 Silver).
3. **⚖️ Claims Adjudication Workbench (`vw_claims_analyst_workbench`)**:
   - Filter claims by Severity Tier (High, Medium, Low) and Status (Pending, Settled).
   - Turnaround SLA compliance indicators (`SLA_BREACH_URGENT`, `ON_TRACK`, `RESOLVED`).
4. **👤 Customer 360 & Risk Tiers (`vw_customer_360`)**:
   - Interactive scatter plot: Lifetime Customer Premium vs. Total Incurred Losses.
   - Bubble size scaled by total policies held.
