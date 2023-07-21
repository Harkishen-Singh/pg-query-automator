package main

import (
	"context"
	"flag"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/timescale/promscale/pkg/log"
	"github.com/wissance/stringFormatter"
)

func main() {
	dbUri := flag.String("db_uri", "", "The database URI to connect to.")
	templatePath := flag.String("template_path", "template.yaml", "Path of the template file that contains queries.")
	schemaPtr := flag.String("schema", "", "Schema of the table. This will fill the {schema} in the template.")
	num_inserts := flag.Int("num_inserts", 100, "Number of insert query txns to be executed per second.")
	num_updates := flag.Int("num_updates", 100, "Number of update query txns to be executed per second.")
	num_deletes := flag.Int("num_deletes", 100, "Number of delete query txns to be executed per second.")
	run_interval := flag.Duration("interval", time.Second, "Intervals in which all the txns will be repeated.")
	level := flag.String("level", "info", "Log level to use from [ 'error', 'warn', 'info', 'debug' ].")
	flag.Parse()

	logCfg := log.Config{
		Format: "logfmt",
		Level: *level,
	}
	if err := log.Init(logCfg); err != nil {
		panic(err)
	}

	if *dbUri == "" {
		log.Fatal("Please provide a database URI using the -db_uri flag.")
	}
	schema := *schemaPtr
	if schema == "" {
		schema = "public"
	}

	conn := getPgxPool(dbUri)
	defer conn.Close()
	testConn(conn)

	template := get_template(*templatePath)
	var (
		r_str, r_str1, r_str2 string
		execCount             int64
	)

	ticker := time.NewTicker(*run_interval)
	defer ticker.Stop()
	for range ticker.C {
		insert_queries := make([]string, 0, *num_inserts)
	out1:
		for {
			for i := 0; i < len(template); i++ {
				r_str, r_str1, r_str2 = RandomString(10), RandomString(10), RandomString(10)
				execCount = template[i].GetExecutionCount()
				table := stringFormatter.FormatComplex(template[i].Table, map[string]interface{}{"schema": schema})
				query := stringFormatter.FormatComplex(template[i].Queries.Insert, map[string]interface{}{"table": table, "schema": schema, "execution_count": execCount, "r_str": r_str, "r_str1": r_str1, "r_str2": r_str2})
				template[i].SetExecutionCount(execCount + 1)
				log.Debug("insert_query", query)
				insert_queries = append(insert_queries, query)
				if len(insert_queries) == *num_inserts {
					break out1
				}
			}
		}

		update_queries := make([]string, 0, *num_updates)
	out2:
		for {
			for i := 0; i < len(template); i++ {
				r_str, r_str1, r_str2 = RandomString(10), RandomString(10), RandomString(10)
				execCount = template[i].GetExecutionCount()
				table := stringFormatter.FormatComplex(template[i].Table, map[string]interface{}{"schema": schema})
				query := stringFormatter.FormatComplex(template[i].Queries.Update, map[string]interface{}{"table": table, "schema": schema, "execution_count": execCount, "r_str": r_str, "r_str1": r_str1, "r_str2": r_str2})
				template[i].SetExecutionCount(execCount + 1)
				log.Debug("update_query", query)
				update_queries = append(update_queries, query)
				if len(update_queries) == *num_updates {
					break out2
				}
			}
		}

		delete_queries := make([]string, 0, *num_deletes)
	out3:
		for {
			for i := 0; i < len(template); i++ {
				r_str, r_str1, r_str2 = RandomString(10), RandomString(10), RandomString(10)
				execCount = template[i].GetExecutionCount()
				table := stringFormatter.FormatComplex(template[i].Table, map[string]interface{}{"schema": schema})
				query := stringFormatter.FormatComplex(template[i].Queries.Delete, map[string]interface{}{"table": table, "schema": schema, "execution_count": execCount, "r_str": r_str, "r_str1": r_str1, "r_str2": r_str2})
				template[i].SetExecutionCount(execCount + 1)
				log.Debug("delete_query", query)
				delete_queries = append(delete_queries, query)
				if len(delete_queries) == *num_deletes {
					break out3
				}
			}
		}

		log.Debug("total_query_txns_to_be_executed", len(insert_queries)+len(update_queries)+len(delete_queries))
		run := func(queries []string) {
			for i := range queries {
				go func(i int) {
					if _, err := conn.Exec(context.Background(), queries[i]); err != nil {
						panic(fmt.Sprintf("query: %s, error: %s", queries[i], err.Error()))
					}
				}(i)
			}
		}
		run(insert_queries)
		run(update_queries)
		run(delete_queries)
		log.Info("msg", "scheduled_queries", "inserts", len(insert_queries), "updates", len(update_queries), "deletes", len(delete_queries))
	}
}

func getPgxPool(uri *string) *pgxpool.Pool {
	dbpool, err := pgxpool.New(context.Background(), *uri)
	if err != nil {
		log.Fatal("Unable to connect to database: %v", err)
	}
	log.Info("msg", "connected to the database")
	return dbpool
}

func testConn(conn *pgxpool.Pool) bool {
	var t int
	if err := conn.QueryRow(context.Background(), "SELECT 1").Scan(&t); err != nil {
		panic(err)
	}
	return true
}
