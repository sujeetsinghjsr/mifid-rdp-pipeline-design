# DSL Data Extraction Rules — Trade Linkage

## What is the DSL extraction layer?

Before any linkage logic runs, a DSL data extraction layer reads all required
field values from the incoming MXML using XPaths defined in an Excel file.
That Excel file is stored on AWS S3 and loaded at component startup.
When XPaths change: update the Excel, drop it in S3, restart the component.
No code change required.

## Rules

| Variable Name | XPath | Rule Type | Notes |
|---|---|---|---|
| tradeReference | /MxML/trades/trade/tradeHeader/tradeViews/tradeView/tradeId/tradeInternalId | Plain XPath | Primary lookup key (NB) |
| contractId | /MxML/contracts/contract/contractId/internalId | Plain XPath | Stored for reference only |
| creatorContractId | /MxML/contracts/contract/contractHeader/contractSource/contractCreatorReference/businessObjectId/identifier | Plain XPath | Secondary lookup key |
| rootContract | /MxML/contracts/contract/contractId/rootContract | Plain XPath | Does not change in MX3 |
| creatorTradeId | /MxML/trades/trade/tradeHeader/tradeSource/tradeCreatorId | Plain XPath | CREATOR_NB equivalent |
| version | cf_to_integer(/MxML/trades/trade/businessObjectId/versionIdentifier/versionRevision/versionNumber) | CF function | Converts string to integer |
| mifidEventCategory | /MxML/rdhEnrichmentData/mifidLinkType | Plain XPath | PF / NPF / NRPT |
| rdhEventName | /MxML/rdhEnrichmentData/rdhEventName | Plain XPath | RDH event name |
| cloneMessageType | /MxML/rdhEnrichmentData/message | Plain XPath | base or clone |

## CF Custom Functions Used

| Function | Purpose |
|---|---|
| cf_to_integer(xpath) | Converts XPath string result to integer |
| cf_concat(val1, sep, val2) | Joins two values with separator |
| cf_if(condition, true_val, false_val) | Conditional (replaces if/else) |
| string-length(normalize-space(xpath)) > 0 | Check if field has a value (not empty) |
