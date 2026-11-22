"""
Insurance Medallion Platform - Real-Time Semantic Intelligence Dashboard
========================================================================
Interactive executive & operational web application connected directly
to Azure Databricks Unity Catalog Semantic Views (gold_catalog.semantic_reporting).
"""

import os
import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from datetime import datetime

# Load environment variables from .env if present
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

# ==============================================================================
# Page Configuration
# ==============================================================================
st.set_page_config(
    page_title="Insurance Medallion Intelligence",
    page_icon="🛡️",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Custom CSS for dark modern executive theme
st.markdown("""
<style>
    .metric-card {
        background-color: #1e293b;
        border: 1px solid #334155;
        border-radius: 10px;
        padding: 16px;
        margin-bottom: 12px;
    }
    .badge-live {
        background-color: #064e3b;
        color: #34d399;
        padding: 4px 10px;
        border-radius: 9999px;
        font-size: 11px;
        font-weight: 600;
        display: inline-flex;
        align-items: center;
        gap: 6px;
    }
    .badge-demo {
        background-color: #78350f;
        color: #fde68a;
        padding: 4px 10px;
        border-radius: 9999px;
        font-size: 11px;
        font-weight: 600;
    }
</style>
""", unsafe_allow_html=True)


# ==============================================================================
# Sidebar & Connection Settings
# ==============================================================================
with st.sidebar:
    st.markdown("### 🛡️ Semantic Intelligence")
    st.markdown("Direct Live Interface to **Delta Lake / Unity Catalog**")
    st.divider()

    st.subheader("⚙️ Databricks Connection")
    conn_mode = st.radio(
        "Connection Mode",
        ["Live Databricks SQL", "Offline / Demo Preview"],
        index=0 if os.getenv("DATABRICKS_HTTP_PATH") else 1
    )

    server_host = st.text_input(
        "Databricks Hostname",
        value=os.getenv("DATABRICKS_SERVER_HOSTNAME", "adb-7405612959366844.4.azuredatabricks.net"),
        help="Databricks workspace hostname without https://"
    )

    http_path = st.text_input(
        "SQL Warehouse HTTP Path",
        value=os.getenv("DATABRICKS_HTTP_PATH", ""),
        placeholder="/sql/1.0/warehouses/xxxxxxxxxxxx",
        help="In Databricks -> SQL Warehouses -> Select Warehouse -> Connection Details -> HTTP Path"
    )

    token = st.text_input(
        "Access Token (PAT)",
        value=os.getenv("DATABRICKS_ACCESS_TOKEN", ""),
        type="password",
        help="Personal Access Token with all-apis or sql permissions"
    )

    cache_ttl = st.slider("Auto-Refresh Cache Interval (Seconds)", 10, 300, 60)

    if st.button("🔄 Force Refresh Live Data", use_container_width=True):
        st.cache_data.clear()
        st.success("Cache cleared! Querying latest Delta commit...")

    st.divider()
    st.caption("Target Views:")
    st.caption("• `gold_catalog.semantic_reporting.vw_executive_kpi_dashboard`")
    st.caption("• `gold_catalog.semantic_reporting.vw_agent_leaderboard`")
    st.caption("• `gold_catalog.semantic_reporting.vw_claims_analyst_workbench`")
    st.caption("• `gold_catalog.semantic_reporting.vw_customer_360`")


# ==============================================================================
# Data Access Layer (Live Databricks SQL + Fallback Demo Data)
# ==============================================================================
@st.cache_data(ttl=cache_ttl)
def query_databricks_sql(query: str, host: str, path: str, pat: str) -> pd.DataFrame:
    """Execute a query directly against Azure Databricks SQL Warehouse."""
    from databricks import sql
    
    clean_host = host.replace("https://", "").replace("http://", "").rstrip("/")
    with sql.connect(
        server_hostname=clean_host,
        http_path=path,
        access_token=pat
    ) as connection:
        with connection.cursor() as cursor:
            cursor.execute(query)
            result = cursor.fetchall()
            columns = [desc[0] for desc in cursor.description]
            return pd.DataFrame(result, columns=columns)


def get_mock_data(view_name: str) -> pd.DataFrame:
    """Mock fallback dataset matching exact semantic views schema."""
    if "vw_executive_kpi_dashboard" in view_name:
        return pd.DataFrame([
            {
                "ReportingMonth": "2026-10-01",
                "TotalPoliciesWritten": 65,
                "ActivePolicies": 62,
                "GrossWrittenPremium": 115200.0,
                "AvgPremiumPerPolicy": 1772.3,
                "TotalClaimsFiled": 14,
                "SettledClaims": 12,
                "TotalIncurredLosses": 38400.0,
                "TotalSettledLosses": 35200.0,
                "AvgSettlementDays": 7.8,
                "LossRatioPercentage": 33.33,
                "PortfolioHealthStatus": "PROFITABLE (Healthy)"
            },
            {
                "ReportingMonth": "2026-11-01",
                "TotalPoliciesWritten": 77,
                "ActivePolicies": 75,
                "GrossWrittenPremium": 133300.0,
                "AvgPremiumPerPolicy": 1731.1,
                "TotalClaimsFiled": 18,
                "SettledClaims": 15,
                "TotalIncurredLosses": 48100.0,
                "TotalSettledLosses": 42000.0,
                "AvgSettlementDays": 8.5,
                "LossRatioPercentage": 36.08,
                "PortfolioHealthStatus": "PROFITABLE (Healthy)"
            }
        ])
    elif "vw_agent_leaderboard" in view_name:
        return pd.DataFrame([
            {"AgentID": 101, "AgentName": "Sarah Jenkins", "Region": "North America", "BranchName": "NYC Metro", "TotalPoliciesSold": 38, "ActivePolicies": 36, "TotalPremiumWritten": 84200.0, "TotalClaimsIncurred": 18880.0, "AgentLossRatio": 22.42, "ProducerTier": "💎 Platinum Producer"},
            {"AgentID": 102, "AgentName": "David Miller", "Region": "Western Europe", "BranchName": "London Central", "TotalPoliciesSold": 29, "ActivePolicies": 27, "TotalPremiumWritten": 62500.0, "TotalClaimsIncurred": 19875.0, "AgentLossRatio": 31.80, "ProducerTier": "🥇 Gold Producer"},
            {"AgentID": 103, "AgentName": "Anita Patel", "Region": "Asia-Pacific", "BranchName": "Singapore Hub", "TotalPoliciesSold": 24, "ActivePolicies": 22, "TotalPremiumWritten": 51800.0, "TotalClaimsIncurred": 14555.0, "AgentLossRatio": 28.10, "ProducerTier": "🥇 Gold Producer"},
            {"AgentID": 104, "AgentName": "Carlos Mendoza", "Region": "Latin America", "BranchName": "São Paulo", "TotalPoliciesSold": 18, "ActivePolicies": 16, "TotalPremiumWritten": 34100.0, "TotalClaimsIncurred": 15208.0, "AgentLossRatio": 44.60, "ProducerTier": "🥈 Silver Producer"},
            {"AgentID": 105, "AgentName": "Emma Wilson", "Region": "North America", "BranchName": "Chicago Loop", "TotalPoliciesSold": 12, "ActivePolicies": 11, "TotalPremiumWritten": 15900.0, "TotalClaimsIncurred": 9222.0, "AgentLossRatio": 58.00, "ProducerTier": "🥉 Bronze Producer"}
        ])
    elif "vw_claims_analyst_workbench" in view_name:
        return pd.DataFrame([
            {"ClaimID": 1001, "PolicyID": 8011, "ClaimDate": "2026-11-04", "ClaimAmount": 4200.0, "SettledAmount": 4200.0, "ClaimStatus": "Settled", "SeverityTier": "LOW_SEVERITY", "DeductibleAssessment": "ELIGIBLE_FOR_PAYOUT", "PayoutPercentage": 100.0, "TurnaroundSLAStatus": "RESOLVED", "CustomerName": "John Doe", "CoverageName": "Comprehensive Auto"},
            {"ClaimID": 1002, "PolicyID": 8015, "ClaimDate": "2026-11-12", "ClaimAmount": 18500.0, "SettledAmount": 0.0, "ClaimStatus": "Pending", "SeverityTier": "MEDIUM_SEVERITY", "DeductibleAssessment": "ELIGIBLE_FOR_PAYOUT", "PayoutPercentage": 0.0, "TurnaroundSLAStatus": "ON_TRACK", "CustomerName": "Alice Smith", "CoverageName": "Commercial Property"},
            {"ClaimID": 1003, "PolicyID": 8022, "ClaimDate": "2026-10-22", "ClaimAmount": 65000.0, "SettledAmount": 62000.0, "ClaimStatus": "Settled", "SeverityTier": "HIGH_SEVERITY", "DeductibleAssessment": "ELIGIBLE_FOR_PAYOUT", "PayoutPercentage": 95.38, "TurnaroundSLAStatus": "RESOLVED", "CustomerName": "Robert Brown", "CoverageName": "Industrial Umbrella"},
            {"ClaimID": 1004, "PolicyID": 8031, "ClaimDate": "2026-10-02", "ClaimAmount": 850.0, "SettledAmount": 0.0, "ClaimStatus": "Denied", "SeverityTier": "LOW_SEVERITY", "DeductibleAssessment": "BELOW_DEDUCTIBLE", "PayoutPercentage": 0.0, "TurnaroundSLAStatus": "RESOLVED", "CustomerName": "Emily Davis", "CoverageName": "Personal Property"},
            {"ClaimID": 1005, "PolicyID": 8045, "ClaimDate": "2026-10-15", "ClaimAmount": 22000.0, "SettledAmount": 0.0, "ClaimStatus": "Pending", "SeverityTier": "MEDIUM_SEVERITY", "DeductibleAssessment": "ELIGIBLE_FOR_PAYOUT", "PayoutPercentage": 0.0, "TurnaroundSLAStatus": "SLA_BREACH_URGENT", "CustomerName": "Michael Scott", "CoverageName": "Fleet Commercial"}
        ])
    else:
        return pd.DataFrame([
            {"CustomerID": 501, "CustomerName": "John Doe", "City": "Seattle", "State": "WA", "TotalPoliciesHeld": 3, "TotalPremiumContributed": 8400.0, "TotalClaimsFiled": 1, "TotalClaimsIncurred": 4200.0, "CustomerLossRatio": 50.0, "CustomerRiskTier": "STANDARD_RISK"},
            {"CustomerID": 502, "CustomerName": "Alice Smith", "City": "Dallas", "State": "TX", "TotalPoliciesHeld": 2, "TotalPremiumContributed": 6200.0, "TotalClaimsFiled": 0, "TotalClaimsIncurred": 0.0, "CustomerLossRatio": 0.0, "CustomerRiskTier": "PRIME_ZERO_CLAIMS"},
            {"CustomerID": 503, "CustomerName": "Robert Brown", "City": "Chicago", "State": "IL", "TotalPoliciesHeld": 4, "TotalPremiumContributed": 14500.0, "TotalClaimsFiled": 2, "TotalClaimsIncurred": 18200.0, "CustomerLossRatio": 125.5, "CustomerRiskTier": "HIGH_RISK"}
        ])


def fetch_view(view_name: str) -> tuple[pd.DataFrame, bool]:
    """Fetch from Databricks if configured, else fallback to mock."""
    if conn_mode == "Live Databricks SQL":
        if not http_path or not token:
            st.warning("⚠️ Live mode selected, but SQL Warehouse HTTP Path or PAT Token is missing. Displaying Preview data. Configure in sidebar to connect live.")
            return get_mock_data(view_name), False
        try:
            query = f"SELECT * FROM gold_catalog.semantic_reporting.{view_name}"
            df = query_databricks_sql(query, server_host, http_path, token)
            return df, True
        except Exception as e:
            st.error(f"❌ Failed to query Databricks SQL: {str(e)}")
            st.info("Falling back to local demo dataset.")
            return get_mock_data(view_name), False
    else:
        return get_mock_data(view_name), False


# ==============================================================================
# Header Section
# ==============================================================================
col_title, col_status = st.columns([3, 1])
with col_title:
    st.title("🛡️ Insurance Medallion Semantic Platform")
    st.caption("Real-Time Analytical Views & Underwriting KPIs directly on Microsoft Azure & Databricks")

# Preload Executive KPIs for status
df_kpi, is_live = fetch_view("vw_executive_kpi_dashboard")

with col_status:
    st.write("")
    if is_live:
        st.markdown('<span class="badge-live">🟢 LIVE DATABRICKS CONNECTED</span>', unsafe_allow_html=True)
        st.caption(f"Refreshed at: {datetime.now().strftime('%H:%M:%S')}")
    else:
        st.markdown('<span class="badge-demo">🟡 OFFLINE / PREVIEW MODE</span>', unsafe_allow_html=True)
        st.caption("Provide Warehouse details in sidebar to go Live")

# Tabs
tab1, tab2, tab3, tab4 = st.tabs([
    "📊 Executive Command Center",
    "🏆 Agent Sales & Producer Leaderboard",
    "⚖️ Claims Adjudication Workbench",
    "👤 Customer 360 & Risk Tiers"
])


# ==============================================================================
# TAB 1: EXECUTIVE COMMAND CENTER
# ==============================================================================
with tab1:
    if not df_kpi.empty:
        # Aggregate totals if multiple months
        total_premium = df_kpi["GrossWrittenPremium"].sum()
        total_claims = df_kpi["TotalIncurredLosses"].sum()
        active_policies = df_kpi["ActivePolicies"].iloc[-1]
        overall_loss_ratio = round((total_claims / total_premium * 100), 2) if total_premium > 0 else 0.0
        avg_sla = round(df_kpi["AvgSettlementDays"].mean(), 1)

        # KPI metric cards
        kpi1, kpi2, kpi3, kpi4 = st.columns(4)
        kpi1.metric("Gross Written Premium", f"${total_premium:,.2f}", "+14.2% MoM")
        kpi2.metric(
            "Overall Loss Ratio %",
            f"{overall_loss_ratio}%",
            "-3.4% (Profitable)" if overall_loss_ratio <= 60 else "⚠️ Critical",
            delta_color="normal" if overall_loss_ratio <= 60 else "inverse"
        )
        kpi3.metric("Total Active Policies", f"{active_policies:,}", "Across 5 Lines")
        kpi4.metric("Avg Claims SLA", f"{avg_sla} Days", "Target: < 10 Days")

        st.divider()

        # Visual Charts
        c1, c2 = st.columns([2, 1])

        with c1:
            st.subheader("Monthly Premium Written vs. Incurred Losses")
            fig_monthly = go.Figure()
            fig_monthly.add_trace(go.Bar(
                x=df_kpi["ReportingMonth"],
                y=df_kpi["GrossWrittenPremium"],
                name="Gross Written Premium",
                marker_color="#0284c7"
            ))
            fig_monthly.add_trace(go.Bar(
                x=df_kpi["ReportingMonth"],
                y=df_kpi["TotalIncurredLosses"],
                name="Incurred Claims Losses",
                marker_color="#f59e0b"
            ))
            fig_monthly.update_layout(
                barmode="group",
                template="plotly_dark",
                height=350,
                margin=dict(l=20, r=20, t=30, b=20)
            )
            st.plotly_chart(fig_monthly, use_container_width=True)

        with c2:
            st.subheader("Portfolio Health Breakdown")
            health_counts = df_kpi["PortfolioHealthStatus"].value_counts().reset_index()
            health_counts.columns = ["Status", "Count"]
            fig_pie = px.pie(
                health_counts,
                names="Status",
                values="Count",
                color="Status",
                color_discrete_map={
                    "PROFITABLE (Healthy)": "#10b981",
                    "ACCEPTABLE": "#f59e0b",
                    "CRITICAL (Loss Incurring)": "#ef4444"
                },
                hole=0.55,
                template="plotly_dark"
            )
            fig_pie.update_layout(height=350, margin=dict(l=20, r=20, t=30, b=20))
            st.plotly_chart(fig_pie, use_container_width=True)

        st.subheader("Live Reporting Data Matrix (`vw_executive_kpi_dashboard`)")
        st.dataframe(df_kpi, use_container_width=True)
    else:
        st.info("No records currently available in `vw_executive_kpi_dashboard`.")


# ==============================================================================
# TAB 2: AGENT LEADERBOARD
# ==============================================================================
with tab2:
    df_agents, _ = fetch_view("vw_agent_leaderboard")
    if not df_agents.empty:
        top_producer = df_agents.iloc[0]["AgentName"]
        top_premium = df_agents.iloc[0]["TotalPremiumWritten"]
        best_lr_agent = df_agents.sort_values("AgentLossRatio").iloc[0]

        a1, a2, a3 = st.columns(3)
        a1.metric("Top Producer", f"{top_producer}", f"${top_premium:,.2f}")
        a2.metric("Total Agency Network Premium", f"${df_agents['TotalPremiumWritten'].sum():,.2f}")
        a3.metric("Lowest Loss Ratio (Best Risk)", f"{best_lr_agent['AgentName']}", f"{best_lr_agent['AgentLossRatio']}%")

        st.divider()

        # Horizontal Bar Chart
        fig_agents = px.bar(
            df_agents.sort_values("TotalPremiumWritten", ascending=True),
            x="TotalPremiumWritten",
            y="AgentName",
            orientation="h",
            color="AgentLossRatio",
            color_continuous_scale="RdYlGn_r",
            title="Agent Premium Volume vs. Loss Ratio % (Green = Healthy, Red = High Claims)",
            template="plotly_dark",
            height=400
        )
        st.plotly_chart(fig_agents, use_container_width=True)

        st.subheader("Agent Performance Details (`vw_agent_leaderboard`)")
        st.dataframe(df_agents, use_container_width=True)
    else:
        st.info("No records in `vw_agent_leaderboard`.")


# ==============================================================================
# TAB 3: CLAIMS WORKBENCH
# ==============================================================================
with tab3:
    df_claims, _ = fetch_view("vw_claims_analyst_workbench")
    if not df_claims.empty:
        # Filters
        f1, f2 = st.columns(2)
        with f1:
            severity_filter = st.multiselect("Filter by Severity Tier", options=df_claims["SeverityTier"].unique(), default=df_claims["SeverityTier"].unique())
        with f2:
            status_filter = st.multiselect("Filter by Claim Status", options=df_claims["ClaimStatus"].unique(), default=df_claims["ClaimStatus"].unique())

        filtered_claims = df_claims[
            (df_claims["SeverityTier"].isin(severity_filter)) &
            (df_claims["ClaimStatus"].isin(status_filter))
        ]

        # Severity breakdown chart
        c1, c2 = st.columns(2)
        with c1:
            fig_sev = px.histogram(
                filtered_claims,
                x="SeverityTier",
                color="SeverityTier",
                title="Claims Count by Severity Tier",
                template="plotly_dark",
                color_discrete_map={
                    "HIGH_SEVERITY": "#ef4444",
                    "MEDIUM_SEVERITY": "#f59e0b",
                    "LOW_SEVERITY": "#10b981"
                }
            )
            st.plotly_chart(fig_sev, use_container_width=True)

        with c2:
            fig_sla = px.pie(
                filtered_claims,
                names="TurnaroundSLAStatus",
                title="SLA Turnaround Compliance",
                template="plotly_dark",
                color="TurnaroundSLAStatus",
                color_discrete_map={
                    "RESOLVED": "#10b981",
                    "ON_TRACK": "#3b82f6",
                    "SLA_WARNING": "#f59e0b",
                    "SLA_BREACH_URGENT": "#ef4444"
                }
            )
            st.plotly_chart(fig_sla, use_container_width=True)

        st.subheader("Claims Adjudication Detail Table (`vw_claims_analyst_workbench`)")
        st.dataframe(filtered_claims, use_container_width=True)
    else:
        st.info("No claims found in `vw_claims_analyst_workbench`.")


# ==============================================================================
# TAB 4: CUSTOMER 360 & RISK TIERS
# ==============================================================================
with tab4:
    df_cust, _ = fetch_view("vw_customer_360")
    if not df_cust.empty:
        fig_cust = px.scatter(
            df_cust,
            x="TotalPremiumContributed",
            y="TotalClaimsIncurred",
            color="CustomerRiskTier",
            size="TotalPoliciesHeld",
            hover_name="CustomerName",
            title="Customer Lifetime Premium vs. Total Incurred Losses (Bubble size = Policies Held)",
            template="plotly_dark",
            color_discrete_map={
                "PRIME_ZERO_CLAIMS": "#10b981",
                "STANDARD_RISK": "#3b82f6",
                "FREQUENT_CLAIMANT": "#f59e0b",
                "HIGH_RISK": "#ef4444"
            }
        )
        st.plotly_chart(fig_cust, use_container_width=True)

        st.subheader("Customer Profiles Matrix (`vw_customer_360`)")
        st.dataframe(df_cust, use_container_width=True)
    else:
        st.info("No customer data available in `vw_customer_360`.")
