# Oracle APEX JSON Benchmark — SQL vs PL/SQL Loop

Companion repository for the article:  
**"We improved the query by 40% and the report was still slow"**

This repo contains everything needed to reproduce the benchmark on your own Oracle database:
a real anime dataset loaded from MyAnimeList, two JSON-building methods in an Oracle package,
an ORDS handler, and a timing procedure that measures the difference.

---

## The Story

While working at a client site I discovered a slow ORDS REST service. The culprit was
the way JSON was being built — a PL/SQL loop using `JSON_OBJECT_T` and `JSON_ARRAY_T`,
which causes hundreds of context switches between the PL/SQL and SQL engines.

Replacing it with a single SQL statement using `JSON_OBJECT` and `JSON_ARRAYAGG` made
the service 3–4x faster. This repo proves it with real benchmark numbers.

The test data is anime from [MyAnimeList](https://myanimelist.net) via the
[Jikan API](https://jikan.moe) — because if you have to write benchmark scripts,
you might as well use data you actually enjoy.

---

## Benchmark Results

Measured directly inside Oracle 19c on OCI, pure database execution time, 5 warm runs averaged:

| Row limit | SQL method | Loop method | Loop is slower by |
|-----------|-----------|-------------|-------------------|
| 100 rows  | 8.1 ms    | 31.4 ms     | **3.9x**          |
| 500 rows  | 53 ms     | 155 ms      | **2.9x**          |

---

## Requirements

- Oracle Database 19c or higher
- Oracle APEX workspace (for ORDS handler)
- Python 3 + `requests` library (only if re-fetching data from Jikan)

---

## Run Order

### Step 1 — Create the schema
```sql
-- Run in SQL Workshop
@schema/01_ani_schema_ddl.sql
```

### Step 2 — Load the data
Run these four files in order in SQL Workshop (split due to file size limits):
```sql
@data/02a_ani_insert_lookups.sql     -- genres, studios, seasons
@data/02b_ani_insert_anime_1.sql     -- anime rows 1-249
@data/02b_ani_insert_anime_2.sql     -- anime rows 250-499
@data/02c_ani_insert_anime_genre.sql -- genre bridge links
```

### Step 3 — Compile the package
Run spec first, then body (two separate executions in SQL Workshop):
```sql
@packages/ani_api_pkg.sql
```

### Step 4 — Test the package directly
```sql
SELECT ani_api.get_anime_sql(10)  FROM dual;
SELECT ani_api.get_anime_loop(10) FROM dual;
```

### Step 5 — Register the ORDS handler
In APEX → SQL Workshop → RESTful Services, create:
- Module: `ani.benchmark`  base path: `/ani/`
- Template: `anime/list`
- GET handler: paste content of `ords/ani_ords_handler_simple.sql`

### Step 6 — Run the benchmark
```sql
-- Create log table + procedure, then execute:
@benchmark/04_ani_benchmark.sql
```

---

## Re-fetching Fresh Data from Jikan

If you want to reload with current MyAnimeList data instead of using the included inserts:

```bash
pip3 install requests
python3 scripts/fetch_jikan_to_sql.py
```

This generates a fresh `02_ani_data_inserts.sql` file. Edit `MAX_PAGES` at the top
of the script to control how many anime are fetched (default: 20 pages = 500 anime).

---

## Repo Structure

```
oracle-apex-json-benchmark/
├── schema/
│   └── 01_ani_schema_ddl.sql          -- DDL: all ANI_ tables and indexes
├── data/
│   ├── 02a_ani_insert_lookups.sql     -- genres, studios, seasons
│   ├── 02b_ani_insert_anime_1.sql     -- anime part 1
│   ├── 02b_ani_insert_anime_2.sql     -- anime part 2
│   └── 02c_ani_insert_anime_genre.sql -- genre bridge
├── packages/
│   └── ani_api_pkg.sql                -- spec + body: get_anime_sql, get_anime_loop
├── ords/
│   └── ani_ords_handler_simple.sql    -- ORDS handler source
├── benchmark/
│   └── 04_ani_benchmark.sql           -- timing procedure + results query
└── scripts/
    └── fetch_jikan_to_sql.py          -- Python: fetch Jikan → generate INSERT SQL
```

---

## License

MIT — use freely, attribution appreciated.
