-- RDP Trade Data Linkage Table
-- ANZ MiFID II Regulatory Data Pipeline
-- Source: Kear Chea design authority session, 28 Jul 2026

CREATE TABLE RDP_TRADE_DATA_LINKAGE (

    -- Waterfall lookup columns (positioned first for debugging efficiency)
    TRADE_REFERENCE       VARCHAR2(100)  NOT NULL,
    CREATOR_TRADE_ID      VARCHAR2(100),
    CONTRACT_ID           VARCHAR2(100),
    ROOT_CONTRACT         VARCHAR2(100),

    -- MiFID II linkage
    MIFID_LINK_ID         VARCHAR2(50),
    MIFID_PARENT_LINK_ID  VARCHAR2(50),

    -- G20 linkage (future — not in current scope)
    G20_LINK_ID           VARCHAR2(50),
    G20_PARENT_LINK_ID    VARCHAR2(50),

    -- LBMA linkage (future — pending Kear session)
    LBMA_LINK_ID          VARCHAR2(50),
    LBMA_PARENT_LINK_ID   VARCHAR2(50),

    -- Eligibility flag
    IS_NRPT               CHAR(1)        DEFAULT 'N',
    CONSTRAINT chk_nrpt CHECK (IS_NRPT IN ('Y', 'N')),

    -- Event metadata
    RDH_EVENT             VARCHAR2(100),

    -- Audit columns
    CREATED_TIMESTAMP     TIMESTAMP      DEFAULT CURRENT_TIMESTAMP NOT NULL,
    UPDATED_TIMESTAMP     TIMESTAMP,

    -- Primary key
    CONSTRAINT pk_trade_linkage PRIMARY KEY (TRADE_REFERENCE, CREATED_TIMESTAMP)
);

-- Index for waterfall lookups
CREATE INDEX idx_tl_trade_ref ON RDP_TRADE_DATA_LINKAGE (TRADE_REFERENCE);
CREATE INDEX idx_tl_creator   ON RDP_TRADE_DATA_LINKAGE (CREATOR_TRADE_ID);
CREATE INDEX idx_tl_mifid_lnk ON RDP_TRADE_DATA_LINKAGE (MIFID_LINK_ID);
