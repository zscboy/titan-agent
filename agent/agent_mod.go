package agent

import (
	"archive/zip"
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"

	"github.com/bodgit/sevenzip"
	lua "github.com/yuin/gopher-lua"
)

const ExecTimeout = 10

type AgentModule struct {
	agent *Agent
}

func newAgentModule(agent *Agent) *AgentModule {
	am := &AgentModule{agent: agent}

	return am
}

func (am *AgentModule) loader(L *lua.LState) int {
	// register functions to the table
	var exports = map[string]lua.LGFunction{
		"fileMD5":        am.fileMD5,
		"info":           am.info,
		"extract7z":      am.extract7z,
		"extractZip":     am.extractZip,
		"copyDir":        am.copyDir,
		"removeAll":      am.removeAll,
		"execWithDetach": am.execWithDetach,
	}

	mod := L.SetFuncs(L.NewTable(), exports)

	// returns the module
	L.Push(mod)
	return 1
}

func (ag *AgentModule) fileMD5(L *lua.LState) int {
	filePath := L.CheckString(1)
	if len(filePath) == 0 {
		L.Push(lua.LNil)
		L.Push(lua.LString("File path can not empty"))
	}

	md5, err := fileMD5(filePath)
	if err != nil {
		L.Push(lua.LNil)
		L.Push(lua.LString(fmt.Sprintf("%s", err)))
		return 2
	}

	L.Push(lua.LString(md5))
	return 1
}

func fileMD5(filePath string) (string, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return "", err
	}
	defer file.Close()

	hash := md5.New()

	if _, err := io.Copy(hash, file); err != nil {
		return "", err
	}

	md5Bytes := hash.Sum(nil)
	return hex.EncodeToString(md5Bytes), nil
}

func (am *AgentModule) info(L *lua.LState) int {
	t := L.NewTable()
	t.RawSet(lua.LString("wdir"), lua.LString(am.agent.args.WorkingDir))
	t.RawSet(lua.LString("version"), lua.LString(am.agent.Version()))
	t.RawSet(lua.LString("id"), lua.LString(am.agent.ID()))

	L.Push(t)
	return 1
}

func (am *AgentModule) extract7z(L *lua.LState) int {
	filePath := L.CheckString(1)
	outputDir := L.OptString(2, filepath.Dir(filePath))

	err := extract7z(filePath, outputDir)
	if err != nil {
		L.Push(lua.LString(err.Error()))
	} else {
		L.Push(lua.LNil)
	}
	return 1

}

func extract7z(archive string, outputDir string) error {
	err := os.MkdirAll(outputDir, os.ModePerm)
	if err != nil {
		return err
	}

	r, err := sevenzip.OpenReader(archive)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		if err = extract7zFile(f, outputDir); err != nil {
			return err
		}
	}

	return nil
}

func extract7zFile(file *sevenzip.File, outputDir string) error {
	rc, err := file.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	if file.FileInfo().IsDir() {
		os.MkdirAll(outputDir+"/"+file.Name, os.ModePerm)
		return nil
	}
	// Extract the file

	outFile, err := os.Create(outputDir + "/" + file.Name)
	if err != nil {
		return err
	}

	_, err = io.Copy(outFile, rc)
	return err
}

func (am *AgentModule) extractZip(L *lua.LState) int {
	filePath := L.CheckString(1)
	outputDir := L.OptString(2, filepath.Dir(filePath))

	err := extractZip(filePath, outputDir)
	if err != nil {
		L.Push(lua.LString(err.Error()))
	} else {
		L.Push(lua.LNil)
	}
	return 1
}

func extractZip(filePath, outputDir string) error {
	err := os.MkdirAll(outputDir, os.ModePerm)
	if err != nil {
		return err
	}

	zipFile, err := zip.OpenReader(filePath)
	if err != nil {
		return err
	}
	defer zipFile.Close()

	// Extract each file in the ZIP archive
	for _, f := range zipFile.File {
		if err = extractZipFile(f, outputDir); err != nil {
			return err
		}
	}
	return nil
}

func extractZipFile(file *zip.File, outputDir string) error {
	rc, err := file.Open()
	if err != nil {
		return err
	}
	defer rc.Close()

	if file.FileInfo().IsDir() {
		os.MkdirAll(outputDir+"/"+file.Name, os.ModePerm)
		return nil
	}
	// Extract the file

	outFile, err := os.Create(outputDir + "/" + file.Name)
	if err != nil {
		return err
	}

	_, err = io.Copy(outFile, rc)
	return err
}

func (am *AgentModule) copyDir(L *lua.LState) int {
	srcDir := L.ToString(1)
	dstDir := L.ToString(2)

	err := copyDir(srcDir, dstDir)
	if err != nil {
		L.Push(lua.LString(fmt.Sprintf("Error copying directory: %s", err.Error())))
	} else {
		L.Push(lua.LNil)
	}
	return 1
}

func copyFile(src, dst string) error {
	srcFile, err := os.Open(src)
	if err != nil {
		return err
	}
	defer srcFile.Close()

	dstFile, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer dstFile.Close()

	_, err = io.Copy(dstFile, srcFile)
	return err
}

func copyDir(srcDir, dstDir string) error {
	return filepath.Walk(srcDir, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		if !info.IsDir() {
			relPath, err := filepath.Rel(srcDir, path)
			if err != nil {
				return err
			}
			dstPath := filepath.Join(dstDir, relPath)
			if err := os.MkdirAll(filepath.Dir(dstPath), os.ModePerm); err != nil {
				return err
			}

			if err := copyFile(path, dstPath); err != nil {
				return err
			}
		}
		return nil
	})
}

func (am *AgentModule) removeAll(L *lua.LState) int {
	err := os.RemoveAll(L.CheckString(1))
	if err != nil {
		L.Push(lua.LString(err.Error()))
		return 1
	} else {
		L.Push(lua.LNil)
		return 1
	}
}

func (am *AgentModule) execWithDetach(L *lua.LState) int {
	command := L.CheckString(1)
	// timeout := time.Duration(L.OptInt64(2, ExecTimeout)) * time.Second
	var cmd *exec.Cmd

	switch runtime.GOOS {
	case "linux", "darwin":
		cmd = exec.Command("sh", "-c", command)
	case "windows":
		cmd = exec.Command("cmd.exe", "/C", command)
	default:
		L.Push(lua.LString(`unsupported os`))
		return 1
	}

	cmd.Stdin = nil
	cmd.Stdout = nil
	cmd.Stderr = nil

	if err := cmd.Start(); err != nil {
		L.Push(lua.LString(err.Error()))
		return 1
	}

	if err := cmd.Process.Release(); err != nil {
		L.Push(lua.LString(err.Error()))
		return 1
	}

	L.Push(lua.LNil)
	return 1

}
