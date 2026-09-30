from pathlib import Path

repo = Path(__file__).resolve().parents[2]
paths = (repo / "cortetsu/utils/Paths.qml").read_text(encoding="utf-8")
file_dialog = (repo / "cortetsu/base/components/filedialog/FolderContents.qml").read_text(encoding="utf-8")

for root in ("data", "state", "cache", "config"):
    assert f"readonly property string {root}" in paths
assert paths.count("}/cortetsu`") == 4
assert "import Caelestia" not in paths
assert "Caelestia.Config" not in paths
assert "/cortetsu" in paths
assert "CORTETSU_RECORDINGS_DIR" in paths
assert "function toLocalFile" in paths and "function absolutePath" in paths
for name, fallback in (
    ("downloads", "Descargas"),
    ("desktop", "Escritorio"),
    ("documents", "Documentos"),
    ("music", "Música"),
    ("pictures", "Imágenes"),
    ("videos", "Vídeos"),
    ("templates", "Plantillas"),
    ("publicShare", "Público"),
):
    assert f"property string {name}" in paths
    assert fallback in paths
assert "function userDirectory(name: string)" in paths
for name in ("Downloads", "Desktop", "Documents", "Music", "Pictures", "Videos", "Templates", "Public"):
    assert f'case "{name}"' in paths
assert "Paths.userDirectory(root.dialog.cwd[1])" in file_dialog
assert "root.dialog.cwd.slice(2)" in file_dialog
print("PASS: compatibility Paths routes all XDG runtime roots to Cortetsu")
