# Notion Tracker Setup

> **Navigation**: [← Back to REO Testing](../README.md)

Instructions for setting up the Notion-based test tracker from [NotionTracker.csv](NotionTracker.csv).

## Import into Notion

1. Open Notion, navigate to the workspace where you want the tracker
2. Click **Import** (sidebar → Import, or `...` menu → Import)
3. Select **CSV** and upload `NotionTracker.csv`
4. Notion creates a database from the CSV

## Configure Column Types

After import, change these column types in the database:

| Column    | Change to    | Notes                                                           |
| --------- | ------------ | --------------------------------------------------------------- |
| Indexer A | **Checkbox** | Indexer marks when they've completed the test                   |
| Indexer B | **Checkbox** | Same                                                            |
| Indexer C | **Checkbox** | Same                                                            |
| Status    | **Select**   | Options: Not Started, In Progress, Pass, Fail, Blocked, Skipped |
| Link      | **URL**      | Links are already full GitHub URLs                              |
| Plan      | **Select**   | Enables grouping by test plan (Baseline / Eligibility)          |

### Add Indexer Columns

If you have more than 3 indexers, add additional checkbox columns. Rename the generic "Indexer A/B/C" columns to the actual indexer names or addresses.

## Recommended Views

### 1. Main Tracker (Table)

Default view — all tests in sequence. Sort by **Test ID**.

### 2. By Plan (Board)

Board view grouped by **Plan**. Shows progress through Baseline vs Eligibility at a glance.

### 3. Per-Indexer (Filtered Tables)

Create a filtered table for each indexer showing their checkbox and status columns.

### 4. Blocked / Failed

Filter: Status = Fail or Blocked. Use during testing to track issues.

## Workflow

1. **Before testing**: Share the Notion page with participating indexers (edit access)
2. **During testing**: Indexers check their checkbox when they complete a test. Update Status column.
3. **Coordinator**: Updates Status and Notes columns as tests progress
4. **After each session**: Review blocked/failed tests, update Notes with details

## Column Reference

| Column      | Purpose                                            |
| ----------- | -------------------------------------------------- |
| Test ID     | Unique identifier (e.g. B-3.2 = Baseline test 3.2) |
| Plan        | Test plan: Baseline or Eligibility                 |
| Test Name   | Short test title                                   |
| Link        | Link to detailed test steps in IndexerTestGuide.md |
| Indexer A-C | Checkboxes for each indexer to confirm completion  |
| Status      | Current test status                                |
| Notes       | Free text for issues, observations, tx hashes      |

---

**Related**: [NotionTracker.csv](NotionTracker.csv) | [IndexerTestGuide.md](../IndexerTestGuide.md)
