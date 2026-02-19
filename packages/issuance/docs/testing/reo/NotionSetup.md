# Notion Tracker Setup

> **Navigation**: [← Back to REO Testing](README.md) | [Status](Status.md)

Instructions for setting up the Notion-based test tracker from [NotionTracker.csv](NotionTracker.csv).

## Import into Notion

1. Open Notion, navigate to the workspace where you want the tracker
2. Click **Import** (sidebar → Import, or `...` menu → Import)
3. Select **CSV** and upload `NotionTracker.csv`
4. Notion creates a database with all 53 tests (22 baseline + 31 REO)

## Configure Column Types

After import, change these column types in the database:

| Column    | Change to    | Notes                                                           |
| --------- | ------------ | --------------------------------------------------------------- |
| Indexer A | **Checkbox** | Indexer marks when they've completed the test                   |
| Indexer B | **Checkbox** | Same                                                            |
| Indexer C | **Checkbox** | Same                                                            |
| Status    | **Select**   | Options: Not Started, In Progress, Pass, Fail, Blocked, Skipped |
| Link      | **URL**      | See [Fix Links](#fix-links) below                               |
| Cycle     | **Number**   | Enables sorting by cycle                                        |
| Plan      | **Select**   | Baseline / REO                                                  |
| Executor  | **Select**   | Indexer, Operator, Oracle, etc.                                 |

### Add Indexer Columns

If you have more than 3 indexers, add additional checkbox columns. Rename the generic "Indexer A/B/C" columns to the actual indexer names or addresses.

### Fix Links

The `Link` column contains relative paths like `BaselineTestPlan.md#11-setup-indexer-via-explorer`. To make them clickable, prefix with the GitHub base URL:

```
https://github.com/graphprotocol/contracts/blob/reo-testing/packages/issuance/docs/testing/reo/
```

For example: `BaselineTestPlan.md#11-setup-indexer-via-explorer` becomes:

```
https://github.com/graphprotocol/contracts/blob/reo-testing/packages/issuance/docs/testing/reo/BaselineTestPlan.md#11-setup-indexer-via-explorer
```

You can bulk-edit these in Notion or use find-and-replace before import.

## Recommended Views

### 1. Main Tracker (Table)

Default view — all tests in sequence. Group by **Plan**, then sort by **Cycle** and **Test ID**.

### 2. By Cycle (Board)

Board view grouped by **Cycle Name**. Shows progress through each testing phase at a glance.

### 3. Indexer A/B/C (Filtered Tables)

Create a filtered table for each indexer showing only tests relevant to them (Executor = "Indexer" or their specific role).

### 4. Blocked / Failed

Filter: Status = Fail or Blocked. Use during testing to track issues.

## Workflow

1. **Before testing**: Share the Notion page with participating indexers (edit access)
2. **During testing**: Indexers check their checkbox when they complete a test. Update Status column.
3. **Coordinator**: Updates Status and Notes columns as tests progress
4. **After each session**: Review blocked/failed tests, update Notes with details

## Column Reference

| Column      | Purpose                                                             |
| ----------- | ------------------------------------------------------------------- |
| Test ID     | Unique identifier (B-1.1 = Baseline test 1.1, R-1.1 = REO test 1.1) |
| Plan        | Which test plan (Baseline or REO)                                   |
| Cycle       | Cycle number within the plan                                        |
| Cycle Name  | Human-readable cycle description                                    |
| Test Name   | Short test title                                                    |
| Description | One-line summary of what's being tested                             |
| Executor    | Who runs this test (Indexer, Operator, Oracle, etc.)                |
| Link        | Link to detailed test steps in the markdown doc                     |
| Indexer A-C | Checkboxes for each indexer to confirm completion                   |
| Status      | Current test status                                                 |
| Notes       | Free text for issues, observations, tx hashes                       |

---

**Related**: [NotionTracker.csv](NotionTracker.csv) | [BaselineTestPlan.md](BaselineTestPlan.md) | [ReoTestPlan.md](ReoTestPlan.md) | [Status.md](Status.md)
