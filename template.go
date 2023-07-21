package main

import (
	"io/ioutil"
	"sync"

	"github.com/timescale/promscale/pkg/log"
	"gopkg.in/yaml.v2"
)

type Query struct {
	Insert string `yaml:"insert"`
	Update string `yaml:"update"`
	Delete string `yaml:"delete"`
}

type Table struct {
	Table          string `yaml:"table"`
	Queries        Query  `yaml:"queries"`
	ExecutionCount int64
	mu             sync.RWMutex
}

func (t *Table) SetExecutionCount(count int64) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.ExecutionCount = count
}

func (t *Table) GetExecutionCount() int64 {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.ExecutionCount
}

func get_template(file string) []Table {
	data, err := ioutil.ReadFile(file)
	if err != nil {
		log.Fatal("error: %v", err)
	}

	tables := make([]Table, 0)
	err = yaml.Unmarshal(data, &tables)
	if err != nil {
		log.Fatal("error", err)
	}
	log.Info("total_tables", len(tables))
	return tables
}
