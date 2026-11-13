# ADR-008: Premium sobria, el lenguaje de composición de Cortetsu 3.0

## Estado

**ACCEPTED, implementación por fases.** Decisión del propietario del 2026-11-12
([plan maestro](../roadmap/CORTETSU_3_0_PLAN_MAESTRO.md)). El avance real de
cada fase está en [`REGISTRO.md`](../roadmap/cortetsu-3.0/REGISTRO.md); este
documento fija las decisiones, no afirma que estén terminadas.

## Contexto

Las superficies de Cortetsu 2.x comparten tokens y primitivas, pero se
componen cada una a su manera: paneles con marco dentro de otro panel con
marco, bloques con altura fija aunque tengan una sola fila, y tarjetas iguales
para datos de distinto peso. Los tres temas (Ink, Washi, Kurogane) ya dan
color, material y tipografía; faltaba una gramática común para decidir qué
lleva marco, qué es una fila y qué es protagonista.

## Decisión

Premium sobria es esa gramática. No es un cuarto tema y no cambia la paleta de
ninguno: Ink sigue en sumi e índigo, Washi en papel y Kurogane en acero con sus
esquinas firmes.

### 1. Formas por rol

Cada rol usa un token que ya existía. No se añade un radio por rol: un alias
sin valor propio sería una segunda fuente de verdad.

| Rol | Uso | Token y primitiva |
| --- | --- | --- |
| Frame | Ventana o superficie principal. Una por superficie | `radiusSurface`, `CortetsuInkPanel` |
| Section | Un grupo lógico de filas con su título | `radiusMedium`, `SettingsGroup` |
| Island | Hub, popout, control flotante | `radiusSurface`/`radiusLarge`, `CortetsuPopupSurface` |
| Row | Listas y propiedades. Abierta: sin marco en reposo | `rowHeight`, `SettingRow`, `CortetsuListRow` |
| Pill | Pestañas y estados cortos | `radiusMedium`, `CortetsuTab`, `CortetsuTabBar` |
| Hero | El bloque protagonista. Uno por vista | `radiusLarge`, `CortetsuHero` |
| Danger | Olvidar, apagar, fallo de autenticación | `colorVermillion`, confirmación en dos pasos |

### 2. Reglas de composición

1. **Un marco por superficie.** Dos zonas de la misma superficie se distinguen
   por el fondo y una línea fina, no por un segundo panel con borde. Settings
   es la referencia: barra lateral y página comparten marco.
2. **Altura según contenido.** Ningún bloque fija su alto para parecer lleno.
   Una lista mide lo que miden sus filas hasta un máximo y después desplaza.
3. **Filas abiertas.** Una fila solo recibe fondo al pasar el puntero o al
   estar seleccionada. Entre filas va `CortetsuDivider`.
4. **Un protagonista.** El lavado de acento vive en el `CortetsuHero` de la
   vista y en ningún otro bloque de ella.
5. **Un control aparece si tiene con qué trabajar.** Un filtro no se ofrece
   para dos filas; una acción sin backend no se dibuja.
6. **Lo destructivo se confirma.** Olvidar una red o un perfil pide una segunda
   pulsación con el texto de lo que se va a borrar.

### 3. Tokens nuevos

En `[material]` de `ui.toml`, con valor propio por tema en
`theme-profiles.json`:

| Token | Ink | Washi | Kurogane | Para qué |
| --- | --- | --- | --- | --- |
| `separator_alpha` | 0.36 | 0.6 | 0.8 | Fuerza de la línea entre filas y zonas |
| `hero_wash_alpha` | 0.3 | 0.12 | 0.1 | Lavado de acento del bloque protagonista |

Kurogane conserva sus radios 2/4/6/8 y su contorno marcado. El plan pedía
revisar ese contrato "deliberadamente": se revisó y se mantiene, porque la
identidad angular depende de él y las reglas de arriba ya quitan las cajas
repetidas sin tocar los radios.

### 4. Primitivas nuevas

| Primitiva | Sustituye | Prueba |
| --- | --- | --- |
| `CortetsuDivider` | `Rectangle { height: 1; color: Qt.alpha(colorOutlineVariant, …) }` escrito a mano | `tests/qml/components/tst_PremiumSobria.qml` |
| `CortetsuHero` | Tarjetas de estado con alto fijo | ídem |
| `CortetsuFact` | Pares etiqueta/valor sueltos en una franja | ídem |
| `CortetsuTabBar` | Filas de `CortetsuTab` o de botones `active` montadas en cada superficie | ídem |

Los divisores y pestañas existentes migran cuando se rediseña su superficie,
no en un cambio masivo.

### 5. Identidad en la pantalla de bloqueo

El Evolving Mark del bloqueo sigue la autenticación real:

| Estado | Forma |
| --- | --- |
| Sesión bloqueada, incluso al escribir | Ascended |
| PAM rechazó el intento | Monster, hasta que se permite otro intento |
| PAM aceptó, antes de liberar `wl_session_lock` | Cosmic |

Sustituye el mapeo de `docs/design/CORTETSU-PRODUCT-REBUILD.md`. Human y
Awakening se conservan en `assets/branding/` para otros ciclos. La forma nunca
decide el desbloqueo: lo decide PAM y la forma lo sigue.

### 6. Hub

La denominación visible pasa de "Bottom Hub" a "Hub". Los nombres internos
(`BottomHub.qml`, el destino IPC `bottomHub`, las claves de preferencias) se
conservan por compatibilidad.

## Consecuencias

- Las páginas de Settings ganan 48 px de alto y de ancho útil al desaparecer
  el panel interior.
- Los arneses que alojan `settings/Content.qml` deben darle el marco entero,
  como `SettingsHost.qml`.
- Una superficie nueva que necesite un marco dentro de otro debe justificarlo
  en su revisión; el linter ya informa `layout-nested-surface`.
