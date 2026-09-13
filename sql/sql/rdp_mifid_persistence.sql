-- RDP MiFID Data Persistence Tables
-- Two-table architecture confirmed by Kear Chea, 28 Jul 2026

-- TABLE 1: Regime-agnostic eligibility cache
-- Sits BEFORE Jurisdiction Eligibility
-- Contains IDM + EDM only for eligibility determination
CREATE TABLE RDP_MIF_ELIGIBILITY_CACHE (
    MIFID_LINK_ID     VARCHAR2(50)   NOT NULL,
    IDM               VARCHAR2(100),  -- F57 Investment Decision Maker
    EDM               VARCHAR2(100),  -- F59 Execution Decision Maker
    CREATED_TIMESTAMP TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT pk_elig_cache PRIMARY KEY (MIFID_LINK_ID)
);

CREATE INDEX idx_ec_link_id ON RDP_MIF_ELIGIBILITY_CACHE (MIFID_LINK_ID);

-- TABLE 2: Full MiFID persistence — eligible trades only
-- Sits AFTER Jurisdiction Eligibility
-- 8 DSL rules govern field population
CREATE TABLE RDP_MIFID_TRADE_DATA_PERSISTENCE (

    MIFID_LINK_ID     VARCHAR2(50)   NOT NULL,

    -- SOFT_LINK fields (payload first → carry parent if blank)
    MIC               VARCHAR2(20),   -- F36 Market Identifier Code
    VENUE_TX_ID       VARCHAR2(100),  -- F3  Venue Transaction ID

    -- CARRY_OVER fields (NPF: carry · PF: recalculate)
    TRN               VARCHAR2(100),  -- F2  Transaction Reference Number
    TRADING_DATE      TIMESTAMP,      -- F28 Trading Date/Time
    IDM               VARCHAR2(100),  -- F57 Investment Decision Maker
    EDM               VARCHAR2(100),  -- F59 Execution Decision Maker

    -- DELTA_DRIVEN fields (Phase C write-back only — NULL at Write 2)
    QUANTITY          NUMBER(20,6),   -- F30 Quantity
    DECR_INCR         VARCHAR2(10),   -- F32 Notional Increase/Decrease flag
    CONSTRAINT chk_decr CHECK (DECR_INCR IN ('INCR', 'DECR', NULL)),

    -- Status and action
    MIFID_STATUS      VARCHAR2(20)   DEFAULT 'PENDING',
    CONSTRAINT chk_status CHECK (MIFID_STATUS IN
        ('PENDING', 'READING', 'COMPLETE', 'SUPPRESSED', 'ERROR')),
    MIFID_ACTION      VARCHAR2(10),
    CONSTRAINT chk_action CHECK (MIFID_ACTION IN ('NEWT', 'REPL', 'CANC', NULL)),

    -- Audit
    CREATED_TIMESTAMP TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    UPDATED_TIMESTAMP TIMESTAMP,

    CONSTRAINT pk_mifid_persist PRIMARY KEY (MIFID_LINK_ID, CREATED_TIMESTAMP)
);

-- Indexes for Phase A polling and Phase C write-back
CREATE INDEX idx_mp_status  ON RDP_MIFID_TRADE_DATA_PERSISTENCE (MIFID_STATUS);
CREATE INDEX idx_mp_link_id ON RDP_MIFID_TRADE_DATA_PERSISTENCE (MIFID_LINK_ID);
