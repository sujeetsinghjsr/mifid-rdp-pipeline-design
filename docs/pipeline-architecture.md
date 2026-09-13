# RDP Pipeline Architecture — ANZ MiFID II

## 9 Processing Stages

| Stage | Component | Purpose |
|---|---|---|
| 1 | De-Dup + Pre-Filter | Remove synthetic Luxor events, filter by message type |
| 2 | MX Message Type Identifier | Identify MxML and Package message types |
| 3 | Trade Event Enricher | Classify event as S&P / MiFID / LBMA type |
| 4 | GT Enrichment | Enrich with LEI, MIC, IDM, EDM, Venue type |
| 5 | JSON Data Products Creator | Normalise 35+ MxML types to 1 flat JSON |
| 6 | ANNA Data Enricher | Resolve ISIN (realtime API or EOD cache) |
| 7 | Trade Linkage | Assign MIFID_LINK_ID via NB/CREATOR_NB waterfall |
| 8 | Data Persistence | Write eligibility cache + full MiFID persistence |
| 9 | Aggregator / Delta Check | Phase A-D: poll, check, submit, update |

## Key Design Decisions

1. NB not CONTRACT_ID for Trade Linkage (FX Swap leg ambiguity)
2. Two-table persistence (race condition on simultaneous events)
3. Delta runs on outbound table not JSON layer (regime-specific fields)
4. DSL XPaths on AWS S3 (hot reload — no code change on XPath update)
5. IS_NRPT in linkage table (not persistence) — eligibility flag only
