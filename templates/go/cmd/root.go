package main

import (
	"fmt"
	"os"
)

// root.go — Application entry point and command router.
// This is the single entry point for {{PROJECT_NAME}}.

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: {{PROJECT_NAME}} <command>")
		fmt.Println("Commands: serve, migrate")
		os.Exit(1)
	}

	switch os.Args[1] {
	case "serve":
		runServer()
	case "migrate":
		runMigrate()
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", os.Args[1])
		os.Exit(1)
	}
}
