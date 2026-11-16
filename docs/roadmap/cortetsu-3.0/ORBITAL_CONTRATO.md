# Orbital: contrato del catálogo Rust

Estado: implementación sin verificar del catálogo; integración completa de reproducción pendiente.

Invocación: `cortetsu-desktop-runtime cortetsu-orbital catalog [ruta-absoluta ...]`.
Las rutas opcionales son contenedores cuyos hijos inmediatos son wallpapers con
`project.json`. No se recorre el disco ni se inicia Steam o un renderizador.

Salida JSON única, schemaVersion 1:

- `entries`: entradas ordenadas por `id` (ruta canónica), deduplicadas.
- `assets`: directorios existentes `steamapps/common/wallpaper_engine/assets`.
- `errors`: objetos `{path,error}` de descubrimiento; no implican que la lista esté completa.

Cada entrada contiene `id`, `location`, `source` (`steam` o `custom`),
`workshopId` (solo carpetas Steam numéricas), `modified` (segundos Unix del
  directorio), `title`, `author`, `preview`, `type`, `properties`, `compatibility`
y `errors`. Los campos ausentes son null, no metadatos inventados. `entrypoint`
aparece cuando se pudo leer el proyecto. Preview y entrypoint solo se exponen
si resuelven a archivos dentro del directorio del wallpaper; se rechazan rutas
absolutas, `..` y enlaces que escapen. `properties` conserva el objeto del autor,
sin ejecutarlo. No se infiere resolución a partir de nombres.

`compatibility` es `undetermined` hasta inspección por backend o `read-error`
cuando falla project.json. No se considera Web incompatible: el soporte depende
del motor concreto. El catálogo no promete que un Scene pueda reproducirse.

Descubrimiento: raíces ~/.local/share/Steam, ~/.steam/steam, ~/.steam/root y
~/.var/app/com.valvesoftware.Steam/.local/share/Steam; libraryfolders.vdf moderno
y antiguo; bibliotecas externas registradas allí. Se normalizan enlaces de las
raíces Steam y se deduplican entradas. Solo se enumeran hijos inmediatos de
steamapps/workshop/content/431960 y contenedores explícitos. VDF y JSON tienen
límite de 2 MiB, cada contenedor 20000 hijos y el catálogo 20000 entradas y
16 MiB de metadatos de entradas serializados (sin contar el sobre JSON). Los
límites se anuncian en errors. VDF no textual o no reconocido produce error,
no una búsqueda alternativa del disco. El contenido de proyectos es no confiable.

El módulo reutiliza el ejecutable Rust existente y serde_json; no añade daemon,
dependencias, copia de recursos ni licencia de motor al repositorio. No escribe
preferencias ni cambia la selección activa. Las raíces personalizadas se pasan
por argumento; su persistencia corresponde al servicio consumidor futuro.

QA posterior: compilar y ejecutar pruebas unitarias escritas (VDF moderno/antiguo,
truncamiento, paths escapados, JSON roto); añadir fixtures Flatpak, alias, disco
desmontado, permisos, límites, errores por entrada y archivo eliminado durante
lectura. No se ejecutaron pruebas/build/lint en esta misión. La lectura de
metadatos no proporciona aislamiento contra modificaciones concurrentes maliciosas
por otros procesos del mismo usuario; el futuro renderizador necesitará su propio
modelo de confianza y recuperación.

Instalación y rollback: no se instala este código durante construcción. En la
futura instalación autorizada, incluir este módulo en el binario de una generación
nueva, conservando la generación anterior. Revertir la generación restaura el
helper anterior; el catálogo no migra ni modifica datos del usuario.
