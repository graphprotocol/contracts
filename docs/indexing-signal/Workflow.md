# Workflow

## Iteration Cycle

```
1. Check Status.md "Needs Review"
2. You review, decide, or ask questions
3. I record decision in Status.md "Decisions Made"
4. I implement or update design based on decision
5. I update Status.md (move items, add new ones)
6. Back to 1
```

## File Roles

| File                               | Who updates               | Purpose                                                           |
| ---------------------------------- | ------------------------- | ----------------------------------------------------------------- |
| [Status.md](./Status.md)           | Claude (after every step) | Single source of current state. Start here.                       |
| [Goal.md](./Goal.md)               | Either (rarely)           | Definition of done. Changes only if scope changes.                |
| [Disconnects.md](./Disconnects.md) | Claude                    | Gap tracker. Items get resolved or moved to contract docs.        |
| [Design.md](./Design.md)           | Claude                    | High-level architecture. Updated when design decisions change it. |
| [contracts/\*.md](./contracts/)    | Claude                    | Per-contract detail. Updated when implementation changes.         |

## Conventions

- **Status.md "Needs Review"** is always current — if it's empty, nothing blocks
- **Decisions are final** once recorded — reopen only if new information surfaces
- **Contract files** use a standard template: Purpose, Location, Key Changes, Design, Open Questions
- **Disconnects** are numbered and referenced from Status.md — resolved ones get struck through

## Where to Start

Open [Status.md](./Status.md).
