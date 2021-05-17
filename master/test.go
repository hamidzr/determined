package main

import (
	"fmt"
	"io/ioutil"
	"os"
	"path/filepath"
	"strings"

	"github.com/determined-ai/determined/master/internal/db"
	"github.com/determined-ai/determined/master/pkg/etc"
	"github.com/ghodss/yaml"
)

func check(err error) {
	if err != nil {
		panic(err)
	}
}

func findConfigs(rootDir string) ([]string, error) {
	var files []string
	err := filepath.Walk(rootDir, func(path string, info os.FileInfo, err error) error {
		if strings.HasSuffix(path, ".yaml") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return files, nil
}

func readYamlConfig(path string) ([]byte, error) {
	data, err := ioutil.ReadFile(path)
	if err != nil {
		return nil, err
	}
	jsonBytes, err := yaml.YAMLToJSON(data)
	if err != nil {
		return nil, err
	}
	return jsonBytes, nil
}

func main() {
	config := db.Config{
		Password: "postgres",
		Host:     "127.0.0.1",
		User:     "postgres",
		Name:     "determined",
		Port:     "5432",
	}

	err := etc.SetRootPath("static/srv/")
	if err != nil {
		panic(err)
	}

	db, err := db.Setup(&config)
	defer db.Close()
	if err != nil {
		panic(err)
	}

	confPaths, err := findConfigs("../examples")
	jsonConfigs := make([][]byte, 0)
	for _, configPath := range confPaths {
		config, err := readYamlConfig(configPath)
		if err != nil {
			continue
		}
		jsonConfigs = append(jsonConfigs, config)
	}
	baseExp, err := db.ExperimentByID(1)
	if err != nil {
		panic(err)
	}
	baseExp.ID = 0

	for _, _ = range jsonConfigs {
		newExp := *baseExp
		err = db.AddExperiment(&newExp)
		check(err)
		fmt.Printf("created exp %v\n", newExp.ID)
		_, err = db.RawQuery("test_update_config", 1, "{}")
		if err != nil {
			fmt.Println(err)
		}
	}

	// for _, configPath := range *confPaths {
	// 	config, err := readYamlConfig(configPath)
	// 	if err != nil {
	// 		continue
	// 	}
	// 	db.AddExperiment(baseExp)
	// }

	// db.RawQuery("init")
}
