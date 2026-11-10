// API do TP2: identifica o Pod que atendeu cada requisicao e grava/le
// registros em um PostgreSQL com volume persistente.
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

var (
	db       *sql.DB
	podName  = env("POD_NAME", "local")
	nodeName = env("NODE_NAME", "local")
	appEnv   = env("APP_ENV", "dev")
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func connect() {
	dsn := fmt.Sprintf("host=%s port=%s user=%s password=%s dbname=%s sslmode=disable connect_timeout=3",
		env("DB_HOST", "postgres"), env("DB_PORT", "5432"), env("DB_USER", "app"),
		os.Getenv("DB_PASSWORD"), env("DB_NAME", "app"))
	var err error
	if db, err = sql.Open("postgres", dsn); err != nil {
		log.Fatal(err)
	}
	db.SetMaxOpenConns(5)
	db.SetConnMaxLifetime(time.Minute)
	go func() {
		for {
			_, err := db.Exec(`CREATE TABLE IF NOT EXISTS records (
				id SERIAL PRIMARY KEY,
				message TEXT NOT NULL,
				pod TEXT NOT NULL,
				created_at TIMESTAMPTZ NOT NULL DEFAULT now())`)
			if err == nil {
				log.Print("banco pronto")
				return
			}
			log.Printf("aguardando banco: %v", err)
			time.Sleep(2 * time.Second)
		}
	}()
}

func health(w http.ResponseWriter, r *http.Request) {
	if err := db.PingContext(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db-down", "error": err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func info(w http.ResponseWriter, r *http.Request) {
	var total int
	dbStatus := "ok"
	if err := db.QueryRowContext(r.Context(), "SELECT count(*) FROM records").Scan(&total); err != nil {
		dbStatus = err.Error()
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"pod": podName, "node": nodeName, "env": appEnv,
		"db": dbStatus, "records": total, "time": time.Now().Format(time.RFC3339),
	})
}

type record struct {
	ID        int       `json:"id"`
	Message   string    `json:"message"`
	Pod       string    `json:"pod"`
	CreatedAt time.Time `json:"created_at"`
}

func records(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodPost:
		var in struct {
			Message string `json:"message"`
		}
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil || strings.TrimSpace(in.Message) == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": `envie {"message": "..."}`})
			return
		}
		var rec record
		err := db.QueryRowContext(r.Context(),
			"INSERT INTO records (message, pod) VALUES ($1, $2) RETURNING id, message, pod, created_at",
			in.Message, podName).Scan(&rec.ID, &rec.Message, &rec.Pod, &rec.CreatedAt)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		writeJSON(w, http.StatusCreated, rec)
	case http.MethodGet:
		rows, err := db.QueryContext(r.Context(), "SELECT id, message, pod, created_at FROM records ORDER BY id")
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": err.Error()})
			return
		}
		defer rows.Close()
		out := []record{}
		for rows.Next() {
			var rec record
			if err := rows.Scan(&rec.ID, &rec.Message, &rec.Pod, &rec.CreatedAt); err == nil {
				out = append(out, rec)
			}
		}
		writeJSON(w, http.StatusOK, out)
	default:
		w.WriteHeader(http.StatusMethodNotAllowed)
	}
}

func index(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}
	fmt.Fprintf(w, "TP2 DCC091A - pod %s no node %s\nRotas: /info /health /records (GET, POST)\n", podName, nodeName)
}

func main() {
	connect()
	mux := http.NewServeMux()
	mux.HandleFunc("/", index)
	mux.HandleFunc("/health", health)
	mux.HandleFunc("/info", info)
	mux.HandleFunc("/records", records)
	addr := ":" + env("PORT", "8080")
	log.Printf("ouvindo em %s (pod=%s node=%s)", addr, podName, nodeName)
	log.Fatal(http.ListenAndServe(addr, mux))
}
