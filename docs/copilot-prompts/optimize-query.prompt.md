---
agent: "ask"
description: "Optimize PostgreSQL queries for performance while maintaining security constraints"
---

Optimize the following PostgreSQL query for the backend.

## Optimization Checklist

### Indexing
- Are WHERE clause columns indexed?
- Are JOIN columns indexed?
- Are ORDER BY columns indexed?
- Composite indexes ordered by selectivity (most selective first)?
- No unnecessary indexes (each adds write overhead)?

### Query Structure
- Can subqueries be replaced with JOINs?
- Can `EXISTS` replace `IN` for correlated subqueries?
- Is pagination using keyset (cursor) instead of OFFSET?
- Are unnecessary columns excluded from SELECT?
- Can CTEs be materialized or inlined for better performance?

### Safety Constraints (Non-Negotiable)
- All queries MUST use parameterized placeholders (`$1, $2, ...`)
- Never use `fmt.Sprintf` for query construction
- Always `defer rows.Close()` after `db.Query()`
- Check `rows.Err()` after iteration loops
- Use transactions for multi-step mutations

### Performance Patterns
- Use `EXPLAIN ANALYZE` to verify improvements
- Consider partial indexes for filtered queries
- Use `CREATE INDEX CONCURRENTLY` for production tables
- Batch inserts with `unnest()` for bulk operations

Reference: your project's backend and migration rule files, if it has them
