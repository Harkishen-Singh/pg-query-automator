package main

import (
	"context"
	"flag"
	"strings"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/timescale/promscale/pkg/log"
	"github.com/wissance/stringFormatter"
)

func main() {
	dbUri := flag.String("db_uri", "", "The database URI to connect to.")
	templatePath := flag.String("template_path", "template.yaml", "Path of the template file that contains queries.")
	schemaPtr := flag.String("schema", "", "Schema of the table. This will fill the {schema} in the template. If you have "+
		"same tables across multiple schemas, you can list those schemas separated by commas *without any space*. Eg: -schemas=iot_1,iot_2,iot_3 . "+
		"The query loop will fill these schemas in {schema} based on the number of queries requested.")
	num_inserts := flag.Int("num_inserts", 100, "Number of insert query txns to be executed per second.")
	num_updates := flag.Int("num_updates", 100, "Number of update query txns to be executed per second.")
	num_deletes := flag.Int("num_deletes", 100, "Number of delete query txns to be executed per second.")
	conn_pool_min := flag.Int("pool_conn_min", 10, "Minimum number of connections in the pool.")
	conn_pool_max := flag.Int("pool_conn_max", 20, "Maximum number of connections in the pool.")
	run_interval := flag.Duration("interval", time.Second, "Intervals in which all the txns will be repeated.")
	level := flag.String("level", "info", "Log level to use from [ 'error', 'warn', 'info', 'debug' ].")
	flag.Parse()

	logCfg := log.Config{
		Format: "logfmt",
		Level:  *level,
	}
	if err := log.Init(logCfg); err != nil {
		panic(err)
	}

	if *dbUri == "" {
		log.Fatal("Please provide a database URI using the -db_uri flag.")
	}

	schemas := []string{}
	switch {
	case *schemaPtr == "":
		schemas = append(schemas, "public")
	case strings.Contains(*schemaPtr, ","):
		// Contains multiple schemas.
		schemas = strings.Split(*schemaPtr, ",")
	default:
		schemas = append(schemas, *schemaPtr)
	}

	conn := getPgxPool(dbUri, int32(*conn_pool_min), int32(*conn_pool_max))
	defer conn.Close()
	testConn(conn)

	template := get_template(*templatePath)
	var (
		r_str, r_str1, r_str2 string
		r_int                 int64
		r_f                   float64
		execCount             int64
	)

	ticker := time.NewTicker(*run_interval)
	defer ticker.Stop()
	for {
		insert_queries := make([]string, 0, *num_inserts)
		if *num_inserts > 0 {
		out1:
			for {
				for _, schema := range schemas {
					for i := 0; i < len(template); i++ {
						r_str, r_str1, r_str2, r_int, r_f = RandomString(10), RandomString(10), RandomString(10), RandomInt(), RandomFloat()
						execCount = template[i].GetExecutionCount()
						table := stringFormatter.FormatComplex(template[i].Table, map[string]interface{}{"schema": schema})
						query := stringFormatter.FormatComplex(template[i].Queries.Insert, map[string]interface{}{
							"table":           table,
							"schema":          schema,
							"execution_count": execCount,
							"r_str":           r_str,
							"r_str1":          r_str1,
							"r_str2":          r_str2,
							"r_int":           r_int,
							"r_f":             r_f,
						})
						query = strings.ReplaceAll(query, "\n", " ")
						template[i].SetExecutionCount(execCount + 1)
						log.Debug("insert_query", query)
						insert_queries = append(insert_queries, query)
						if len(insert_queries) >= *num_inserts {
							break out1
						}
					}
				}
			}
		}

		update_queries := make([]string, 0, *num_updates)
		if *num_updates > 0 {
		out2:
			for {
				for _, schema := range schemas {
					for i := 0; i < len(template); i++ {
						r_str, r_str1, r_str2, r_int, r_f = RandomString(10), RandomString(10), RandomString(10), RandomInt(), RandomFloat()
						execCount = template[i].GetExecutionCount()
						table := stringFormatter.FormatComplex(template[i].Table, map[string]interface{}{"schema": schema})
						query := stringFormatter.FormatComplex(template[i].Queries.Update, map[string]interface{}{
							"table":           table,
							"schema":          schema,
							"execution_count": execCount,
							"r_str":           r_str,
							"r_str1":          r_str1,
							"r_str2":          r_str2,
							"r_int":           r_int,
							"r_f":             r_f,
						})
						query = strings.ReplaceAll(query, "\n", " ")
						template[i].SetExecutionCount(execCount + 1)
						log.Debug("update_query", query)
						update_queries = append(update_queries, query)
						if len(update_queries) >= *num_updates {
							break out2
						}
					}
				}
			}
		}

		delete_queries := make([]string, 0, *num_deletes)
		if *num_deletes > 0 {
		out3:
			for {
				for _, schema := range schemas {
					for i := 0; i < len(template); i++ {
						r_str, r_str1, r_str2, r_int, r_f = RandomString(10), RandomString(10), RandomString(10), RandomInt(), RandomFloat()
						execCount = template[i].GetExecutionCount()
						table := stringFormatter.FormatComplex(template[i].Table, map[string]interface{}{"schema": schema})
						query := stringFormatter.FormatComplex(template[i].Queries.Delete, map[string]interface{}{
							"table":           table,
							"schema":          schema,
							"execution_count": execCount,
							"r_str":           r_str,
							"r_str1":          r_str1,
							"r_str2":          r_str2,
							"r_int":           r_int,
							"r_f":             r_f,
						})
						query = strings.ReplaceAll(query, "\n", " ")
						template[i].SetExecutionCount(execCount + 1)
						log.Debug("delete_query", query)
						delete_queries = append(delete_queries, query)
						if len(delete_queries) >= *num_deletes {
							break out3
						}
					}
				}
			}
		}

		total := len(insert_queries) + len(update_queries) + len(delete_queries)
		log.Debug("total_query_txns_to_be_executed", total)
		var wg sync.WaitGroup
		wg.Add(total)
		run := func(queries []string) {
			for i := range queries {
				go func(i int) {
					if _, err := conn.Exec(context.Background(), queries[i]); err != nil {
						log.Error("query", queries[i], "error", err.Error())
					}
					wg.Done()
				}(i)
			}
		}
		start := time.Now()
		run(insert_queries)
		run(update_queries)
		run(delete_queries)
		go func(start time.Time) {
			wg.Wait()
			totalTimeTaken := time.Since(start)
			log.Info("msg", "batch complete", "time_taken", totalTimeTaken.String())
		}(start)
		log.Info("msg", "scheduled_queries", "inserts", len(insert_queries), "updates", len(update_queries), "deletes", len(delete_queries))

		<-ticker.C
	}
}

func getPgxPool(uri *string, min, max int32) *pgxpool.Pool {
	cfg, err := pgxpool.ParseConfig(*uri)
	if err != nil {
		log.Fatal("Error parsing config", err.Error())
	}
	cfg.MinConns = min
	cfg.MaxConns = max
	dbpool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		log.Fatal("Unable to connect to database", err.Error())
	}
	return dbpool
}

func testConn(conn *pgxpool.Pool) bool {
	var t int
	if err := conn.QueryRow(context.Background(), "SELECT 1").Scan(&t); err != nil {
		panic(err)
	}
	log.Info("msg", "connected to the database")
	return true
}
