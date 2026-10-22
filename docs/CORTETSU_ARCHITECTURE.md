# Arquitectura objetivo de Cortetsu

> Este documento conserva la dirección de producto. La implementación actual
> Rust/Go, schema 2, los dominios y los gates están descritos en el
> [contrato del runtime nativo](migration/NATIVE-RUNTIME.md).


## Definición

Cortetsu es un dotfiles reproducible y una plataforma de escritorio personal para CachyOS/Arch. La implementación actual utiliza Caelestia como base visual y de servicios del shell, pero Caelestia no define la identidad ni el alcance final del proyecto.

El producto debe poder reconstruir el entorno completo sin copiar manualmente archivos desde una máquina viva y sin convertir `/etc/xdg/quickshell/caelestia` en una fuente de verdad accidental.

## Principios

1. **Repositorio primero.** El estado deseado nace en Git; el runtime es una instalación derivada.
2. **Actualizaciones seguras.** Todo cambio crítico pasa por staging, validación, backup y rollback.
3. **Compatibilidad explícita.** Los contratos con el shell, Hyprland y Quickshell se versionan.
4. **QML declarativo.** La interfaz dibuja y enlaza estado; la lógica crítica vive en helpers o servicios tipados.
5. **Capacidades, no suposiciones.** HDR, VRR, DDC, GPU, batería y sensores sólo aparecen cuando fueron detectados.
6. **Un solo sistema de superficies.** Foco, input, fullscreen, scrim y exclusión se coordinan centralmente.
7. **Módulos autocontenidos.** Cada módulo declara dependencias, permisos, comandos, estado, pruebas y migraciones.
8. **Privacidad local.** Secretos y datos personales quedan fuera del repositorio.
9. **Procedencia verificable.** Los portes conservan fuente, revisión y tipo de adaptación.
10. **La máquina real decide.** CI y pruebas estáticas complementan, no sustituyen, la verificación en CachyOS/Arch.

## Capas del sistema

### 1. Inventario y paquetes

Una capa declarativa define paquetes obligatorios, opcionales y específicos de hardware. El instalador debe producir un plan antes de escribir.

```text
packages/
├── base.toml
├── desktop.toml
├── development.toml
├── gaming.toml
└── hardware/
```

### 2. Dotfiles de usuario

Configuración versionada para Hyprland, terminal, shell, editores, herramientas de línea de comandos y aplicaciones compatibles. Los archivos privados o dependientes de la máquina se generan desde perfiles y no se copian literalmente.

```text
dotfiles/
└── .config/
    ├── hypr/
    ├── kitty/
    ├── fish/
    ├── git/
    ├── quickshell/
    └── systemd/user/
```

### 3. Adaptador del shell

La capa actual `caelestia/` se conserva mientras se reduce el número de patches. El objetivo es depender de pocos puntos de integración estables:

- host de módulos Cortetsu;
- host de overlays;
- adaptador del Bottom Hub;
- puente de configuración y temas.

Los módulos nuevos no deben añadir una propiedad nueva al `ScreenState` upstream ni otro bloque manual a `ContentWindow` cuando puedan registrarse en un host propio.

### 4. Estado y superficies

Un `CortetsuState` por pantalla administrará estados propios sin contaminar el modelo upstream. Un `SurfaceCoordinator` central resolverá:

- overlay primario activo;
- popouts anclados;
- OSD y toasts transitorios;
- teclado y focus grab;
- regiones de input;
- cierre por fullscreen o cambio de pantalla;
- restauración del foco anterior.

### 5. Backend y acciones

Los comandos críticos se modelarán como acciones tipadas:

```text
SetWallpaper
SetMonitorTopology
SetPowerProfile
SetAudioDevice
SetBrightness
MoveWorkspace
TerminateProcess
ApplyScene
```

Cada acción deberá producir un resultado estructurado y, cuando sea posible, un token de deshacer. QML no debe ejecutar nuevas cadenas arbitrarias con `sh -c`.

### 6. Módulos

```text
modules/<id>/
├── module.toml
├── ui/
├── domain/
├── migrations/
├── tests/
└── README.md
```

El manifiesto define superficies, comandos, capacidades, permisos, dependencias y versión de API.

Módulos first-party iniciales:

- Bottom Hub;
- Overview;
- Clipboard;
- Hardware;
- Display;
- Wallpaper;
- Notes;
- Screen Time;
- Device Link.

### 7. Temas

Un tema de Cortetsu abarcará más que una paleta:

- colores;
- tipografía;
- densidad;
- redondeo;
- elevación;
- transparencia y blur;
- perfil de movimiento;
- iconografía;
- adaptadores para aplicaciones.

La generación se hará en staging, con validación y activación atómica.

### 8. Perfiles de máquina

Los perfiles describen diferencias reales sin crear forks del repositorio:

```text
profiles/
├── common.toml
├── dilan-laptop.toml
└── secrets.example.toml
```

Un perfil puede declarar monitores esperados, paquetes opcionales, GPU, política de batería, aplicaciones favoritas y módulos habilitados. Los secretos se referencian por nombre, nunca por valor.

### 9. Generaciones

La meta es dejar de modificar el runtime vivo durante la construcción:

```text
~/.local/share/cortetsu/generations/
├── 000001-<hash>/
├── 000002-<hash>/
└── current -> 000002-<hash>/
```

Flujo:

```text
plan -> build temporal -> lint/tests -> prueba de arranque -> switch atómico
```

Una generación fallida no sustituye a la última generación saludable.

### 10. Escenas

Las escenas coordinan cambios completos y reversibles:

- Gaming;
- Universidad;
- Batería;
- Presentación;
- Trabajo profundo.

Pueden combinar display, energía, audio, DND, wallpaper, workspaces y aplicaciones. Toda activación automática debe explicar el motivo y ofrecer deshacer.

## Estructura final prevista

```text
Cortetsu/
├── core/
├── shell/
├── modules/
├── adapters/
├── actions/
├── scenes/
├── dotfiles/
├── packages/
├── profiles/
├── themes/
├── generations/
├── migrations/
├── tests/
├── packaging/
└── docs/
```

## Fases de migración

### Fase 0 — Identidad y contrato

- nombre visible Cortetsu;
- manifiesto `cortetsu.toml`;
- CLI unificada;
- registro de identidad y procedencia;
- compatibilidad completa con nombres heredados.

### Fase 1 — Inventario reproducible

- inventario de paquetes, servicios y archivos;
- separación entre estado común, máquina y secreto;
- modo `plan` sin escrituras;
- doctor de dependencias.

### Fase 2 — Dotfiles completos

- mover configuración de usuario a `dotfiles/`;
- instalación por enlaces o generación declarativa;
- perfiles por máquina;
- validación de archivos antes de activarlos.

### Fase 3 — Generaciones y rollback

- construir fuera de `/etc`;
- ejecutar pruebas contra la generación;
- switch atómico;
- rollback y garbage collection.

### Fase 4 — Core y módulos

- `CortetsuState`;
- `SurfaceCoordinator`;
- `ActionBroker`;
- manifests de módulos;
- migración gradual de los módulos actuales.

### Fase 5 — Control Center y escenas

- interfaz unificada;
- historial de acciones;
- automatizaciones explicables;
- API común para QML, CLI y futuras integraciones.

## No objetivos

- copiar íntegramente `uthman_dotfiles`;
- reemplazar archivos nuevos del shell con snapshots antiguos;
- almacenar tokens, contraseñas o datos personales;
- activar funciones de hardware no comprobadas;
- añadir módulos sin pruebas, health check y política de rollback;
- crear un fork total de la base actual antes de demostrar que el adaptador pequeño es insuficiente.

## Criterio de éxito

Cortetsu será un dotfiles superior cuando pueda instalar, verificar, actualizar y revertir el escritorio completo desde Git; cuando sus módulos compartan contratos comunes; y cuando una actualización fallida no pueda dejar la sesión sin un estado recuperable.
