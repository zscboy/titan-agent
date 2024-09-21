package server

import (
	"encoding/json"
	"os"
)

type Config struct {
	LuaFileList      []*File `json:"luaList"`
	BusinessFileList []*File `json:"businessList"`
}

type File struct {
	Version string `json:"version"`
	MD5     string `json:"md5"`
	URL     string `json:"url"`
}

func ParseConfig(filePath string) (*Config, error) {
	buf, err := os.ReadFile(filePath)
	if err != nil {
		return nil, err
	}

	config := Config{}
	err = json.Unmarshal(buf, &config)
	if err != nil {
		return nil, err
	}

	return &config, nil

}
