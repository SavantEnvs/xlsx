// Package fuzzopen is the mining harness for process_cell: unlike the root
// Fuzz, it re-raises the panics that readSheetFromFile recovers into errors,
// so an internal runtime error while opening a workbook is a crash.
package fuzzopen

import (
	"strings"

	"github.com/tealeg/xlsx/v3"
)

func Fuzz(data []byte) int {
	file, err := xlsx.OpenBinary(data)
	if err != nil {
		if strings.Contains(err.Error(), "runtime error:") {
			panic(err)
		}
		return -1
	}
	for _, sheet := range file.Sheets {
		sheet.ForEachRow(func(r *xlsx.Row) error {
			return r.ForEachCell(func(c *xlsx.Cell) error {
				c.String()
				return nil
			})
		})
	}
	return 0
}
