-- ==============================================================================
-- 06_create_semantic_views.sql
-- Description: Creates Unity Catalog Schemas and Business Semantic Views
--              for Power BI, Tableau, Executive Dashboards, and Analytics.
-- Catalogs: silver_catalog, gold_catalog
-- Schemas:  insurance_conformed, insurance_analytics, semantic_reporting
-- ==============================================================================

-- 1. Ensure Unity Catalog Schemas Exist
CREATE SCHEMA IF NOT EXISTS silver_catalog.insurance_conformed;
CREATE SCHEMA IF NOT EXISTS gold_catalog.insurance_analytics;
CREATE SCHEMA IF NOT EXISTS gold_catalog.semantic_reporting;

-- ==============================================================================
-- VIEW 1: Executive KPI Dashboard View (vw_executive_kpi_dashboard)
-- Purpose: C-level view providing Gross Written Premium, Incurred Claims,
--          Loss Ratio %, Total Active Policies, and Average Claims Settlement Days.
-- ==============================================================================
CREATE OR REPLACE VIEW gold_catalog.semantic_reporting.vw_executive_kpi_dashboard AS
WITH PolicyMetrics AS (
    SELECT 
        DATE_TRUNC('month', PolicyStartDate) AS ReportingMonth,
        COUNT(DISTINCT PolicyID) AS TotalPoliciesWritten,
        COUNT(DISTINCT CASE WHEN UPPER(PolicyStatus) = 'ACTIVE' THEN PolicyID END) AS ActivePolicies,
        SUM(COALESCE(PremiumAmount, 0)) AS GrossWrittenPremium,
        AVG(COALESCE(PremiumAmount, 0)) AS AvgPremiumPerPolicy
    FROM silver_catalog.insurance_conformed.fct_policy
    GROUP BY DATE_TRUNC('month', PolicyStartDate)
),
ClaimMetrics AS (
    SELECT 
        DATE_TRUNC('month', ClaimDate) AS ReportingMonth,
        COUNT(DISTINCT ClaimID) AS TotalClaimsFiled,
        COUNT(DISTINCT CASE WHEN UPPER(ClaimStatus) = 'SETTLED' THEN ClaimID END) AS SettledClaims,
        SUM(COALESCE(ClaimAmount, 0)) AS TotalIncurredLosses,
        SUM(COALESCE(SettledAmount, 0)) AS TotalSettledLosses,
        AVG(CASE WHEN SettlementDays IS NOT NULL AND SettlementDays >= 0 THEN SettlementDays END) AS AvgSettlementDays
    FROM silver_catalog.insurance_conformed.fct_claim
    GROUP BY DATE_TRUNC('month', ClaimDate)
)
SELECT 
    COALESCE(p.ReportingMonth, c.ReportingMonth) AS ReportingMonth,
    COALESCE(p.TotalPoliciesWritten, 0) AS TotalPoliciesWritten,
    COALESCE(p.ActivePolicies, 0) AS ActivePolicies,
    ROUND(COALESCE(p.GrossWrittenPremium, 0), 2) AS GrossWrittenPremium,
    ROUND(COALESCE(p.AvgPremiumPerPolicy, 0), 2) AS AvgPremiumPerPolicy,
    COALESCE(c.TotalClaimsFiled, 0) AS TotalClaimsFiled,
    COALESCE(c.SettledClaims, 0) AS SettledClaims,
    ROUND(COALESCE(c.TotalIncurredLosses, 0), 2) AS TotalIncurredLosses,
    ROUND(COALESCE(c.TotalSettledLosses, 0), 2) AS TotalSettledLosses,
    ROUND(COALESCE(c.AvgSettlementDays, 0), 1) AS AvgSettlementDays,
    -- Loss Ratio = (Total Incurred Claims / Gross Written Premium) * 100
    ROUND(
        CASE 
            WHEN COALESCE(p.GrossWrittenPremium, 0) > 0 
            THEN (COALESCE(c.TotalIncurredLosses, 0) / p.GrossWrittenPremium) * 100 
            ELSE 0 
        END, 2
    ) AS LossRatioPercentage,
    -- Underwriting Health Indicator
    CASE 
        WHEN COALESCE(p.GrossWrittenPremium, 0) = 0 THEN 'NO_PREMIUM'
        WHEN (COALESCE(c.TotalIncurredLosses, 0) / p.GrossWrittenPremium) <= 0.60 THEN 'PROFITABLE (Healthy)'
        WHEN (COALESCE(c.TotalIncurredLosses, 0) / p.GrossWrittenPremium) <= 0.75 THEN 'ACCEPTABLE'
        ELSE 'CRITICAL (Loss Incurring)'
    END AS PortfolioHealthStatus
FROM PolicyMetrics p
FULL OUTER JOIN ClaimMetrics c ON p.ReportingMonth = c.ReportingMonth;

-- ==============================================================================
-- VIEW 2: Claims Adjudication & Settlement Workbench (vw_claims_analyst_workbench)
-- Purpose: Operational workbench for claims adjusters to triage high-risk claims,
--          unsettled claims, payout ratios, and SLA turnaround breaches.
-- ==============================================================================
CREATE OR REPLACE VIEW gold_catalog.semantic_reporting.vw_claims_analyst_workbench AS
SELECT 
    c.ClaimID,
    c.ClaimDate,
    c.IncidentDate,
    c.ClaimStatus,
    ROUND(c.ClaimAmount, 2) AS ClaimAmount,
    ROUND(COALESCE(c.SettledAmount, 0), 2) AS SettledAmount,
    c.SettlementDays,
    p.PolicyID,
    p.PolicyStatus,
    p.CoverageCode,
    cov.CoverageName,
    cov.Category AS CoverageCategory,
    p.PremiumAmount,
    p.DeductibleAmount,
    cust.CustomerID,
    cust.FullName AS CustomerName,
    cust.Email AS CustomerEmail,
    cust.Phone AS CustomerPhone,
    agt.AgentID,
    agt.FullName AS AgentName,
    agt.BranchName,
    -- Claim vs Deductible Flag
    CASE 
        WHEN c.ClaimAmount <= COALESCE(p.DeductibleAmount, 0) THEN 'BELOW_DEDUCTIBLE'
        ELSE 'ELIGIBLE_FOR_PAYOUT'
    END AS DeductibleAssessment,
    -- Payout Settlement Ratio %
    ROUND(
        CASE 
            WHEN c.ClaimAmount > 0 THEN (COALESCE(c.SettledAmount, 0) / c.ClaimAmount) * 100 
            ELSE 0 
        END, 2
    ) AS PayoutPercentage,
    -- Severity Tier
    CASE 
        WHEN c.ClaimAmount >= 50000 THEN 'HIGH_SEVERITY'
        WHEN c.ClaimAmount >= 10000 THEN 'MEDIUM_SEVERITY'
        ELSE 'LOW_SEVERITY'
    END AS SeverityTier,
    -- Turnaround SLA Alert (> 30 days pending)
    CASE 
        WHEN UPPER(c.ClaimStatus) = 'PENDING' AND DATEDIFF(CURRENT_DATE(), c.ClaimDate) > 30 THEN 'SLA_BREACH_URGENT'
        WHEN UPPER(c.ClaimStatus) = 'PENDING' AND DATEDIFF(CURRENT_DATE(), c.ClaimDate) > 14 THEN 'SLA_WARNING'
        WHEN UPPER(c.ClaimStatus) = 'PENDING' THEN 'ON_TRACK'
        ELSE 'RESOLVED'
    END AS TurnaroundSLAStatus
FROM silver_catalog.insurance_conformed.fct_claim c
LEFT JOIN silver_catalog.insurance_conformed.fct_policy p ON c.PolicyID = p.PolicyID
LEFT JOIN silver_catalog.insurance_conformed.dim_coverage cov ON p.CoverageCode = cov.CoverageCode
LEFT JOIN silver_catalog.insurance_conformed.dim_customer cust ON p.CustomerID = cust.CustomerID
LEFT JOIN silver_catalog.insurance_conformed.dim_agent agt ON p.AgentID = agt.AgentID;

-- ==============================================================================
-- VIEW 3: Agent Sales & Performance Leaderboard (vw_agent_leaderboard)
-- Purpose: Sales management view ranking agents by Written Premium, Loss Ratio,
--          Policy Count, and Commission Tiers.
-- ==============================================================================
CREATE OR REPLACE VIEW gold_catalog.semantic_reporting.vw_agent_leaderboard AS
WITH AgentMetrics AS (
    SELECT 
        p.AgentID,
        COUNT(DISTINCT p.PolicyID) AS TotalPoliciesSold,
        COUNT(DISTINCT CASE WHEN UPPER(p.PolicyStatus) = 'ACTIVE' THEN p.PolicyID END) AS ActivePolicies,
        SUM(COALESCE(p.PremiumAmount, 0)) AS TotalPremiumWritten,
        COUNT(DISTINCT c.ClaimID) AS AssociatedClaimsCount,
        SUM(COALESCE(c.ClaimAmount, 0)) AS TotalClaimsIncurred
    FROM silver_catalog.insurance_conformed.fct_policy p
    LEFT JOIN silver_catalog.insurance_conformed.fct_claim c ON p.PolicyID = c.PolicyID
    GROUP BY p.AgentID
)
SELECT 
    agt.AgentID,
    agt.FullName AS AgentName,
    agt.Email AS AgentEmail,
    agt.Region,
    agt.BranchName,
    COALESCE(m.TotalPoliciesSold, 0) AS TotalPoliciesSold,
    COALESCE(m.ActivePolicies, 0) AS ActivePolicies,
    ROUND(COALESCE(m.TotalPremiumWritten, 0), 2) AS TotalPremiumWritten,
    COALESCE(m.AssociatedClaimsCount, 0) AS AssociatedClaimsCount,
    ROUND(COALESCE(m.TotalClaimsIncurred, 0), 2) AS TotalClaimsIncurred,
    -- Agent Portfolio Loss Ratio %
    ROUND(
        CASE 
            WHEN COALESCE(m.TotalPremiumWritten, 0) > 0 
            THEN (COALESCE(m.TotalClaimsIncurred, 0) / m.TotalPremiumWritten) * 100 
            ELSE 0 
        END, 2
    ) AS AgentLossRatioPercentage,
    -- Sales Tier Assignment
    CASE 
        WHEN COALESCE(m.TotalPremiumWritten, 0) >= 500000 THEN 'PLATINUM_PRODUCER'
        WHEN COALESCE(m.TotalPremiumWritten, 0) >= 250000 THEN 'GOLD_PRODUCER'
        WHEN COALESCE(m.TotalPremiumWritten, 0) >= 100000 THEN 'SILVER_PRODUCER'
        ELSE 'STANDARD_PRODUCER'
    END AS PerformanceTier,
    DENSE_RANK() OVER (ORDER BY COALESCE(m.TotalPremiumWritten, 0) DESC) AS SalesRank
FROM silver_catalog.insurance_conformed.dim_agent agt
LEFT JOIN AgentMetrics m ON agt.AgentID = m.AgentID;

-- ==============================================================================
-- VIEW 4: Customer 360 & Risk Profile View (vw_customer_360)
-- Purpose: Unified customer intelligence view for customer support, cross-sell,
--          retention modeling, and underwriting risk profiling.
-- ==============================================================================
CREATE OR REPLACE VIEW gold_catalog.semantic_reporting.vw_customer_360 AS
WITH CustomerAggregates AS (
    SELECT 
        p.CustomerID,
        COUNT(DISTINCT p.PolicyID) AS TotalPoliciesHeld,
        COUNT(DISTINCT CASE WHEN UPPER(p.PolicyStatus) = 'ACTIVE' THEN p.PolicyID END) AS ActivePoliciesHeld,
        SUM(COALESCE(p.PremiumAmount, 0)) AS LifetimeCustomerPremium,
        COUNT(DISTINCT c.ClaimID) AS TotalClaimsFiled,
        SUM(COALESCE(c.ClaimAmount, 0)) AS TotalClaimsAmountFiled,
        SUM(COALESCE(c.SettledAmount, 0)) AS TotalClaimsPaidOut
    FROM silver_catalog.insurance_conformed.fct_policy p
    LEFT JOIN silver_catalog.insurance_conformed.fct_claim c ON p.PolicyID = c.PolicyID
    GROUP BY p.CustomerID
)
SELECT 
    cust.CustomerID,
    cust.FullName AS CustomerName,
    cust.Email,
    cust.Phone,
    cust.City,
    cust.State,
    cust.ZipCode,
    COALESCE(ca.TotalPoliciesHeld, 0) AS TotalPoliciesHeld,
    COALESCE(ca.ActivePoliciesHeld, 0) AS ActivePoliciesHeld,
    ROUND(COALESCE(ca.LifetimeCustomerPremium, 0), 2) AS LifetimeCustomerPremium,
    COALESCE(ca.TotalClaimsFiled, 0) AS TotalClaimsFiled,
    ROUND(COALESCE(ca.TotalClaimsAmountFiled, 0), 2) AS TotalClaimsAmountFiled,
    ROUND(COALESCE(ca.TotalClaimsPaidOut, 0), 2) AS TotalClaimsPaidOut,
    -- Customer Lifetime Net Profitability
    ROUND(COALESCE(ca.LifetimeCustomerPremium, 0) - COALESCE(ca.TotalClaimsPaidOut, 0), 2) AS NetCustomerContribution,
    -- Risk Profile Classification
    CASE 
        WHEN COALESCE(ca.TotalClaimsFiled, 0) = 0 THEN 'PRIME (Zero Claims)'
        WHEN COALESCE(ca.TotalClaimsPaidOut, 0) > COALESCE(ca.LifetimeCustomerPremium, 0) THEN 'HIGH_RISK (Unprofitable)'
        WHEN COALESCE(ca.TotalClaimsFiled, 0) >= 3 THEN 'FREQUENT_CLAIMANT'
        ELSE 'STANDARD_RISK'
    END AS CustomerRiskTier,
    -- Cross-Sell Potential Indicator
    CASE 
        WHEN COALESCE(ca.ActivePoliciesHeld, 0) = 1 AND COALESCE(ca.TotalClaimsFiled, 0) = 0 THEN 'PRIME_CROSS_SELL_TARGET'
        WHEN COALESCE(ca.ActivePoliciesHeld, 0) >= 2 THEN 'MULTI_POLICY_LOYAL'
        ELSE 'STANDARD'
    END AS CrossSellOpportunity
FROM silver_catalog.insurance_conformed.dim_customer cust
LEFT JOIN CustomerAggregates ca ON cust.CustomerID = ca.CustomerID;
GO

