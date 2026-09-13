# MiFID II Regulatory Data Pipeline (RDP) — Design & Architecture

Publicis Sapient | Jan 2026 – Present

## Overview

End-to-end design of a **Regulatory Data Pipeline (RDP)** for MiFID II ARM and APA
reporting, processing 35+ Murex MX3 MxML message types through
9 pipeline stages into regulatory submissions.

## Pipeline Architecture

```
Murex MX3 (35+ MxML message types)
    ↓
De-Dup (filtering synthetic Luxor events)
    ↓
MX Message Type Identifier (MxML type / Package type)
    ↓
Trade Event Enricher (S&P / MiFID / LBMA event type)
    ↓
GT Enrichment (LEI · MIC · IDM · EDM · Venue type)
    ↓
JSON Data Products Creator (normalises 35+ MxML to 1 flat JSON)
    ↓
JSON FX SWAP Aggregator (combines NEAR + FAR legs)
    ↓
Post-Filter (removes China data and PIIs)
    ↓
ANNA Data Enricher (resolves ISIN — realtime API + EOD cache)
    ↓
TRADE LINKAGE COMPONENT          ← DSL data extraction (AWS S3)
RDP_TRADE_DATA_LINKAGE (INSERT)
    ↓
DATA PERSISTENCE — Write 1 (eligibility cache) + Write 2 (MiFID table)
RDP_MIF_ELIGIBILITY_CACHE  +  RDP_MIFID_TRADE_DATA_PERSISTENCE
    ↓
Jurisdiction Eligibility (MiFID / LBMA reportability check)
    ↓
Outbound Reporting (Fix + Batch XML transformation)
    ↓
Aggregator / Delta Check (Stage 3: Phase A → B → C → D)
    ↓
ARM (batch 07:30/18:00 AEST)  +  APA (real-time)  →  Trade Repository
```

## Component 1 — Trade Linkage

### Lookup Logic (NB / CREATOR_NB waterfall)

```
PREREQUISITE: DSL data extraction layer runs FIRST
    Extract TRADE_REFERENCE, CREATOR_TRADE_ID, CONTRACT_ID,
    ROOT_CONTRACT, RDH_EVENT, MIFID_EVENT_CATEGORY from MXML
    XPaths maintained in DSL Excel file on AWS S3 — hot reload on restart

STEP 0 — Replay check
    Does TRADE_REFERENCE + TMIT already exist in RDP_TRADE_DATA_LINKAGE?
    YES → replay detected → reuse existing linkage → STOP
    NO  → proceed to Step 1

STEP 1 — TRADE_REFERENCE lookup (regime-agnostic)
    Does TRADE_REFERENCE match existing record in linkage table?
    YES → go to Step 2
    NO  → go to Step 3

STEP 2 — Link type check (regime-specific)
    MiFID NPF → carry forward existing MIFID_LINK_ID
    MiFID PF  → generate new MIFID_LINK_ID, previous → PARENT_LINK_ID
    MiFID NRPT → new MIFID_LINK_ID + set IS_NRPT = Y

STEP 3 — CREATOR_TRADE_ID lookup (regime-agnostic)
    Does CREATOR_TRADE_ID match existing TRADE_REFERENCE in table?
    YES → go to Step 4
    NO  → go to Step 5 (fallback)

STEP 4 — Link type check (same as Step 2)

STEP 5 — Fallback: brand new trade
    Neither found → generate new MIFID_LINK_ID → PARENT_LINK_ID = NULL
```

### Why TRADE_REFERENCE and not CONTRACT_ID?

FX Swap NEAR leg and FAR leg share the same CONTRACT_ID.
CONTRACT_ID cannot distinguish between legs.
TRADE_REFERENCE (tradeOriginId) is unique per leg.

### DSL Extraction Rules (confirmed XPaths)

| Variable | XPath |
|---|---|
| tradeReference | /MxML/trades/trade/tradeHeader/tradeViews/tradeView/tradeId/tradeInternalId |
| contractId | /MxML/contracts/contract/contractId/internalId |
| creatorContractId | /MxML/contracts/contract/contractHeader/contractSource/contractCreatorReference/businessObjectId/identifier |
| rootContract | /MxML/contracts/contract/contractId/rootContract |
| creatorTradeId | /MxML/trades/trade/tradeHeader/tradeSource/tradeCreatorId |
| version | cf_to_integer(/MxML/trades/trade/businessObjectId/versionIdentifier/versionRevision/versionNumber) |
| mifidEventCategory | /MxML/rdhEnrichmentData/mifidLinkType |
| rdhEventName | /MxML/rdhEnrichmentData/rdhEventName |

### Database Schema

```sql
CREATE TABLE RDP_TRADE_DATA_LINKAGE (
    TRADE_REFERENCE      VARCHAR2(100)  NOT NULL,
    CREATOR_TRADE_ID     VARCHAR2(100),
    CONTRACT_ID          VARCHAR2(100),
    ROOT_CONTRACT        VARCHAR2(100),
    G20_LINK_ID          VARCHAR2(50),
    G20_PARENT_LINK_ID   VARCHAR2(50),
    MIFID_LINK_ID        VARCHAR2(50),
    MIFID_PARENT_LINK_ID VARCHAR2(50),
    LBMA_LINK_ID         VARCHAR2(50),
    LBMA_PARENT_LINK_ID  VARCHAR2(50),
    IS_NRPT              CHAR(1)        DEFAULT 'N',
    RDH_EVENT            VARCHAR2(100),
    CREATED_TIMESTAMP    TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    UPDATED_TIMESTAMP    TIMESTAMP
);
```

## Component 2 — Data Persistence (Two-Table Architecture)

### Why Two Tables?

```
PROBLEM:
    Jurisdiction Eligibility needs IDM + EDM from previous event
    to determine MiFID reportability.
    But the full persistence table cannot be read reliably
    when two events arrive within seconds of each other.
    Race condition: Event 2 starts before Event 1 is written.

SOLUTION: Two tables
    Table 1: Regime-agnostic eligibility cache (before Jurisdiction Eligibility)
             → IDM + EDM only + CACHE layer
    Table 2: Full MiFID persistence table (after Jurisdiction Eligibility)
             → eligible trades only → all carry-forward fields
```

### Table 1 — RDP_MIF_ELIGIBILITY_CACHE

```sql
CREATE TABLE RDP_MIF_ELIGIBILITY_CACHE (
    MIFID_LINK_ID     VARCHAR2(50)   NOT NULL,
    IDM               VARCHAR2(100),
    EDM               VARCHAR2(100),
    CREATED_TIMESTAMP TIMESTAMP      DEFAULT CURRENT_TIMESTAMP
);
```

### Table 2 — RDP_MIFID_TRADE_DATA_PERSISTENCE

```sql
CREATE TABLE RDP_MIFID_TRADE_DATA_PERSISTENCE (
    MIFID_LINK_ID     VARCHAR2(50)   NOT NULL,
    MIC               VARCHAR2(20),    -- F36  SOFT_LINK
    VENUE_TX_ID       VARCHAR2(100),   -- F3   SOFT_LINK
    TRN               VARCHAR2(100),   -- F2   CARRY_OVER
    TRADING_DATE      TIMESTAMP,       -- F28  CARRY_OVER
    IDM               VARCHAR2(100),   -- F57  CARRY_OVER
    EDM               VARCHAR2(100),   -- F59  CARRY_OVER
    QUANTITY          NUMBER(20,6),    -- F30  DELTA_DRIVEN (Phase C)
    DECR_INCR         VARCHAR2(10),    -- F32  DELTA_DRIVEN (Phase C)
    MIFID_STATUS      VARCHAR2(20)   DEFAULT 'PENDING',
    MIFID_ACTION      VARCHAR2(10),
    CREATED_TIMESTAMP TIMESTAMP      DEFAULT CURRENT_TIMESTAMP,
    UPDATED_TIMESTAMP TIMESTAMP
);
```

### 8 DSL Rules

| Rule ID | Field | ARM Field | Type | Logic |
|---|---|---|---|---|
| PERS_MIC_SOFTLINK | MIC | F36 | SOFT_LINK | Payload first → carry parent if blank |
| PERS_VENUE_ID_SOFTLINK | Venue Transaction ID | F3 | SOFT_LINK | Current wins → carry if blank |
| PERS_TRN_CARRY | TRN | F2 | CARRY_OVER | NPF carry · PF from LINEAGE table |
| PERS_TRADE_DT_CARRY | Trading Date/Time | F28 | CARRY_OVER | NPF carry · PF re-read payload |
| PERS_IDM_CARRY | IDM | F57 | CARRY_OVER | NPF carry · PF re-derive GT Enrichment |
| PERS_EDM_CARRY | EDM | F59 | CARRY_OVER | NPF carry · PF re-derive GT Enrichment |
| PERS_QTY_DELTA | Quantity | F30 | DELTA_DRIVEN | Phase C write-back only |
| PERS_DECR_INCR_DELTA | Notional INCR/DECR | F32 | DELTA_DRIVEN | Phase C write-back only |

## Component 3 — Delta Check Engine (Stage 3)

```
Phase A: Poll RDP_MIFID_TRADE_DATA_PERSISTENCE
         WHERE MIFID_STATUS = PENDING
         Lock record: MIFID_STATUS = READING

Phase B: Jurisdiction eligibility gate
         IS_NRPT = Y → MIFID_STATUS = SUPPRESSED → skip

Phase C: Delta check on outbound table (outbound vs outbound)
         Compare current event fields vs last submitted for same MIFID_LINK_ID
         No delta → not reportable even if PF
         Delta found → determine MIFID_ACTION:
             No prior submission → MIFID_ACTION = NEWT
             Economic field changed → MIFID_ACTION = REPL
             Cancel event → MIFID_ACTION = CANC
         Write-back to persistence:
             UPDATE RDP_MIFID_TRADE_DATA_PERSISTENCE
             SET QUANTITY = :qty,
                 DECR_INCR = :flag,
                 MIFID_ACTION = :action
             WHERE MIFID_LINK_ID = :link_id

Phase D: ARM/APA submission
         MIFID_STATUS = COMPLETE
```

## Artefacts Produced

- `docs/pipeline-architecture.md` — 9-stage pipeline design with component descriptions
- `docs/trade-linkage-jira.md` — US-014 full Jira story (AC, DoD, validation rules)
- `docs/data-persistence-design.md` — Two-table architecture design rationale
- `sql/rdp_trade_data_linkage.sql` — DDL for Trade Linkage table
- `sql/rdp_mifid_persistence.sql` — DDL for MiFID persistence tables
- `dsl/dsl_extraction_rules.md` — 9 DSL extraction variables with XPaths
- `uat/uat_test_scenarios.md` — 89 UAT scenarios dimensional matrix

## Technology Stack

| Layer | Technology |
|---|---|
| Source System | Murex MX3 (MxML — 35+ message types) |
| Messaging | Kafka / Event Mesh |
| Config / DSL | AWS S3 (Excel XPath rules — hot reload) |
| Data Format | JSON · MxML · XML |
| Database | SQL (Oracle / PostgreSQL) |
| Regulatory Channels | MiFID II ARM · APA · RTS 22 |
| Design Tools | draw.io · JIRA · Confluence |
