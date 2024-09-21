package main

import (
	"agent/server"
	"flag"
	"fmt"
	"net/http"
)

func main() {
	var listenAddress string
	var configFilePath string
	var fileDir string
	flag.StringVar(&listenAddress, "l", "0.0.0.0:8080", "Listen address")
	flag.StringVar(&configFilePath, "config", "./config.json", "The path of config file")
	flag.StringVar(&fileDir, "fs", "./file", "The path of lua script dir")
	flag.Parse()

	config, err := server.ParseConfig(configFilePath)
	if err != nil {
		fmt.Printf("parse config failed:%s\n", err.Error())
		return
	}

	_ = config
	mux := server.NewCustomServerMux(config)

	http.Handle("/", http.FileServer(http.Dir(fileDir)))

	// Start the server
	fmt.Println("Starting server on ", listenAddress)
	http.ListenAndServe(listenAddress, mux)
}
