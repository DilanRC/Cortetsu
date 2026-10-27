# Product

<!-- impeccable:product-schema 1 -->

## Platform

desktop

Escritorio Wayland: Quickshell sobre Qt 6/QML en Hyprland, CachyOS/Arch. No es
web ni móvil; las guías web de Impeccable se aplican adaptadas a QML.

## Users

Un único usuario: Dilan, en su propio portátil y monitores externos. Usa el
escritorio todo el día para programar, estudiar y jugar. Otras personas solo leen
el repositorio como referencia; no hay primer uso ajeno que cuidar.

## Product Purpose

Cortetsu es el shell y los dotfiles personales de Dilan: barra (BottomHub),
popouts, launcher, overview, notificaciones, dashboard, ajustes (SUPER+I),
Hardware Center (SUPER+H), lock, wallpaper y diálogos del sistema. El objetivo es
que todo lo que se ve en el escritorio sea Cortetsu, con un solo lenguaje visual y
de movimiento, y que cada cambio sea reversible por generaciones.

Éxito: ninguna tarea cotidiana abre una ventana ajena (picker de xdph,
polkit-gnome, gcr-prompter, pinentry-gtk, clipse en kitty, fuzzel); las
superficies abren sin esperas perceptibles; nada se rompe al cambiar de monitor o
de escala.

## Positioning

Escritorio personal forjado y verificable: generaciones inmutables con rollback,
backend nativo (Rust/Go) detrás de cada superficie y pruebas por superficie. No es
un tema, ni un fork renombrado de Caelestia, ni una distribución.

## Operating Context

- Uso con teclado primero: atajos SUPER+…, launcher y overview abiertos por tecla.
- Varios monitores (eDP-1 y externos HDMI/DP) y escalas 1.0–2.0.
- Pruebas en Agent Realms y Hyprland anidado; nunca contra la sesión real.
- Instalación con `cortetsu install`, que corre pruebas antes de promover.

## Capabilities and Constraints

- Tokens en `dotfiles/home/.config/cortetsu/ui.toml`, compilados por
  `cortetsu theme compile` a `cortetsu/theme/CortetsuDesign*.{js,qml}`. Nunca se
  editan a mano los generados.
- Primitivos propios en `cortetsu/components/` y `cortetsu/modules/Cortetsu*.qml`;
  `cortetsu/base/` es código heredado de Caelestia 2.4.0 que se migra y se borra.
- Paneles ocultos sin polling; sin `sh -c` en QML; secretos solo por Secret Service.
- Las contraseñas (polkit, llavero, GPG, Wi-Fi) nunca pasan por logs ni por
  `qs ipc` en claro.
- Presupuesto de memoria: el proceso qs no puede empeorar respecto a la fase 4
  (371–379 MiB PSS).

## Brand Commitments

- Nombre: **Cortetsu** (Cortés + *tetsu*, hierro). Sin variantes.
- Paleta de roles sumi / tetsu / washi / índigo (ai) / bermellón (shu). El
  rediseño no cambia esta identidad cromática.
- Índigo para interacción; bermellón solo para atención y peligro.
- Estética samurái contenida: precisión, contraste y *ma* (espacio), sin disfraz
  temático ni emblemas cargados.
- Emblema vigente: Cortetsu Evolving Mark.

## Evidence on Hand

- `docs/IDENTITY.md`, `docs/CORTETSU_DESIGN_SYSTEM.md`, `docs/DESIGN_SYSTEM.md`.
- Capturas de realm en `~/Documentos/Cortetsu-Agent-Realms/evidence/`.
- No hay métricas de uso ni usuarios externos; no se inventan.

## Product Principles

1. Expresivo con criterio: Dilan prefiere superficies con presencia y movimiento.
   La expresividad vive en materiales, composición y transiciones de superficies
   ocasionales; lo que se abre decenas de veces al día por teclado sigue siendo
   inmediato.
2. Todo es Cortetsu: si una tarea del sistema muestra interfaz, la muestra Cortetsu.
3. Estados honestos: carga, error y vacío explícitos; nunca un valor inventado.
4. Reversible y probado: cada superficie entra con pruebas y por generación.

## Accessibility & Inclusion

- Contraste WCAG AA calculado sobre los tokens: 4.5:1 texto, 3:1 controles.
- Cada superficie se usa entera con teclado: foco visible, Enter/Escape, flechas.
- `reducedMotion` existe como preferencia opcional, no como requisito.
