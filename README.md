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

## Build
Clone the repository on your system and ensure that Golang is installed. I compiled using `Go 1.20.5`. Then run
```
go build -o pg-query-automator *.go
```

## Usage

```
Usage of ./pg-query-automator:
  -db_uri string
        The database URI to connect to.
  -interval duration
        Intervals in which all the txns will be repeated. (default 1s)
  -level string
        Log level to use from [ 'error', 'warn', 'info', 'debug' ]. (default "info")
  -num_deletes int
        Number of delete query txns to be executed per second. (default 100)
  -num_inserts int
        Number of insert query txns to be executed per second. (default 100)
  -num_updates int
        Number of update query txns to be executed per second. (default 100)
  -pool_conn_max int
        Maximum number of connections in the pool. (default 20)
  -pool_conn_min int
        Minimum number of connections in the pool. (default 10)
  -schema string
        Schema of the table. This will fill the {schema} in the template. If you have same tables across multiple schemas, you can list those schemas separated by commas *without any space*. Eg: -schemas=iot_1,iot_2,iot_3 . The query loop will fill these schemas in {schema} based on the number of queries requested.
  -template_path string
        Path of the template file that contains queries. (default "template.yaml")
```

See `template.yaml` for examples on how to use.
