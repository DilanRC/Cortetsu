package integration

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestNotificationViewsHaveNoFileWriter(t *testing.T) {
	root := filepath.Join("..", "..", "..")
	for _, name := range []string{"cortetsu/services/Notifs.qml", "cortetsu/modules/CortetsuNotifications.qml"} {
		raw, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			t.Fatal(err)
		}
		source := string(raw)
		if strings.Contains(source, ".setText(") || strings.Contains(source, "setText(JSON") {
			t.Errorf("%s still writes notification state outside the Rust owner", name)
		}
	}
}
