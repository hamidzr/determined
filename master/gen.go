package main

import (
	"fmt"

	"github.com/determined-ai/determined/master/internal/config"
	"github.com/invopop/jsonschema"
)

func main() {
	fmt.Println("vim-go")
	jsonBlob := jsonschema.Reflect(&config.Config{})
	// serialize and print as json
	json, _ := jsonBlob.MarshalJSON()
	fmt.Println(string(json))
}
