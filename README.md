# pg_query_automator
This is a simple program that automates running insert, update, and delete queries against a database.
You can provide a template of SQL queries with templating variables to randomise the values.
This program was developed as a tool that allows me to benchmark logical-decoding on a Postgres based timeseries
database, something pgbench would screw up.

### Why I did not use pgbench?
There were 2 main reasons why I developed this program than using pgbench for running custom-queries:
- Allow insertion of data that has a parameter which should be _strictly increasing_ with each insert, for example,
in the case of timeseries data. This tool provides `{execution_count}` in template that can be used to
insert data with an increasing value. The `{execution_count}` is incremented by 1 whenever a table in the template
is touched. See `template.yaml` for usage example.
- Allow each custom queries to run in a separate transaction. We could run custom queries with pgbench (using -f)
but the queries in the file will execute in 1 big transaction. We could technically wrap in `BEGIN;`, `END;` in the file
so that pgbench runs queries in separate txns, but wrapping for thousands of queries is tedious.

## Usage

```
./pg-query-automator --help
```

See `template.yaml` for examples on how to use.
