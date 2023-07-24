package main

import (
	"math/rand"
	"sync"
	"time"
)

const charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

var (
	mu         sync.Mutex
	r                     = rand.New(rand.NewSource(time.Now().UnixNano()))
	seededRand *rand.Rand = rand.New(rand.NewSource(time.Now().UnixNano()))
)

func stringWithCharset(length int, charset string) string {
	b := make([]byte, length)
	for i := range b {
		b[i] = charset[seededRand.Intn(len(charset))]
	}
	return string(b)
}

func RandomString(length int) string {
	return stringWithCharset(length, charset)
}

func RandomInt() int64 {
	mu.Lock()
	defer mu.Unlock()
	return int64(r.Intn(1_000_000))
}

func RandomFloat() float64 {
	mu.Lock()
	defer mu.Unlock()
	return float64(r.Float32())
}
