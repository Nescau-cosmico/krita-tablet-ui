# Plano de Implementação: Modernização da Interface do Krita para Tablets Android

Documento técnico elaborado a partir da auditoria do código-fonte oficial (`KDE/krita` @ `e6de546`). Nenhum módulo do motor de pintura (`libs/image`, `libs/brush`, `libs/pigment`, `plugins/paintops`) é modificado.

---

## 1. Requisitos Reais do Build Android

> **Nota importante:** o arquivo `krita/README.android.md` upstream está defasado (cita NDK `r18b` e o script removido `androidbuild.sh`). O pipeline real de Android está definido em `krita/CMakeLists.txt`, `krita/packaging/android/apk/build.gradle`, `krita/build-tools/ci-scripts/android.yml` e `krita/build-tools/ci-scripts/build-android-package.py`.

| Componente | Versão / Configuração Exigida | Observação Técnica |
|---|---|---|
| **Host de Compilação** | Linux x86_64 ou Windows + **WSL2 (`Ubuntu-22.04`)** | Permite consumir os binários pré-compilados oficiais do `krita-deps-management` |
| **Android SDK** | `platforms;android-36` + `build-tools;36.0.0` | `minSdkVersion 24`, `targetSdkVersion 36`, `compileSdk 36` |
| **Android NDK** | `27.3.13750724` (r27d LTS) | Alinhamento de página de 16 KB habilitado automaticamente em `arm64-v8a` e `x86_64` |
| **CMake & Build** | `CMake >= 3.30, < 4.0` (ex.: `3.31.10`) + `ccache` | CMake `< 3.25` não popula `CMAKE_ANDROID_NDK_VERSION` exigido no `CMakeLists.txt` |
| **JDK & Gradle** | OpenJDK `17` + Gradle `8.13` (AGP `8.12.0`) | `packaging/android/apk/gradlew` deve manter quebras de linha Unix (`LF`) |
| **Qt & Deps C++** | **Qt 5.15 patcheado pelo Krita** + ~35 libs (`KF5`, `FFmpeg`, `MLT-7`, `Boost`, `LCMS2`, `xsimd`, etc.) | Providos prontos por `teams/ci-artifacts/krita-android-<ABI>` |
| **Scanner QML Host** | `/usr/lib/qt5/bin/qmlimportscanner` (`qtdeclarative5-dev-tools`) | Substitui o binário host de `ext_qt` em `_install/bin/qmlimportscanner` no WSL2 |

> **Regra obrigatória de diretórios (`androiddeployqt`):** `KDECI_WORKDIR_PATH` (onde residem `_build` e `_install`) deve ficar **fora** da árvore raiz de `krita/`, caso contrário o `androiddeployqt` ignora os módulos QML do Qt.

---

## 2. Mapeamento Real do Código (`krita/`, `libs/ui`, `qmlmodules`)

### 2.1. Entrada Android, Ciclo de Vida e Janela Principal
- `krita/packaging/android/apk/AndroidManifest.xml` — Registra `org.krita.android.MainActivity` e carrega `libkrita.so`.
- `krita/packaging/android/apk/src/org/krita/android/MainActivity.java` & `JNIWrappers.java` — Gerenciam modo tela cheia imersivo, `DocumentSaverService` em `onPause()`, intents de arquivo e `JNIWrappers.hasMainWindowLoaded()`.
- `krita/krita/main.cc` — Implementa os callbacks JNI, inicializa OpenGL ES, define `Qt::AA_DontCreateNativeWidgetSiblings` e executa `KisApplication::start(args)`.
- `krita/libs/ui/KisApplication.cpp` & `KisPart.h` — Registram recursos SQLite (`PaintOpPresets`, `Brushes`, `Palettes`), carregam plugins e gerenciam `KisDocument`, `KisView` e `KisMainWindow`.
- `krita/libs/ui/KisMainWindow.h` / `.cpp` — Janela `KXmlGuiWindow` atual que instancia `KisViewManager`, `QMdiArea`, `KoToolBoxFactory` e `QDockWidget`s.
- `krita/libs/ui/KisViewManager.h` / `.cpp` — Hub central de serviços de UI (`canvasBase()`, `canvasResourceProvider()`, `paintOpBox()`, `nodeManager()`, `selectionManager()`, `toolManager()`, `actionManager()`, `inputManager()`, `undoAdapter()`, `switchCanvasOnly(bool)`).

### 2.2. Canvas, Superfícies Nativas e Gestos de Toque
- `krita/libs/ui/canvas/kis_canvas2.h` — Adaptador principal do canvas (`KoCanvasBase`).
- `krita/libs/ui/opengl/kis_opengl_canvas2.h` & `KisOpenGLCanvasRenderer.h` — Superfície nativa `QOpenGLWidget` (`Qt::WA_NativeWindow`) e renderizador de tiles/outline.
- `krita/libs/ui/canvas/on-the-usage-of-native-surfaces-in-krita.md` — Regras de ordenação Z e orçamento de FPS entre superfícies nativas e alien widgets.
- `krita/libs/ui/input/KisCanvasNavigationActionStrategyTouch.h` — Gesto nativo de **pinça para zoom, pan e rotação**.
- `krita/libs/ui/input/KisTouchGestureAction.h` / `.cpp` — Gestos nativos de **dois dedos (`edit_undo`)** e **três dedos (`edit_redo`)**.

### 2.3. Pincéis, Cores, Camadas, Ferramentas e QML Existente
- **Pincéis, Tamanho e Opacidade:** `KisCanvasResourceProvider` (`size()`, `setSize()`, `opacity()`, `setOpacity()`, `currentPreset()`, `setPaintOpPreset()`, `eraserMode()`) + `KisPaintopBox` + `TagFilterProxyModelQmlWrapper` (`"paintoppresets"`).
- **Cores e Histórico:** `KisCanvasResourceProvider` (`fgColor()`, `setFGColor()`, `colorHistoryModel()`) + `KisDisplayColorConverter`.
- **Camadas e Mesclagem:** `KisNodeModel` (`QAbstractItemModel` com miniaturas e papéis de visibilidade/ativo) + `KisNodeManager` (`createNode("KisPaintLayer")`, `duplicateActiveNode()`, `toggleVisibility()`, `setNodeOpacity()`, `setNodeCompositeOp()`) + `KisCompositeOpsModel`.
- **Undo/Redo e Ferramentas:** `KisActionManager` (`"edit_undo"`, `"edit_redo"`, `"erase_action"`) e `KoToolManager` (`"KritaShape/KisToolBrush"`, `"KisToolSelectOutline"`, `"KisToolTransform"`, `"KritaSelected/KisToolColorSampler"`).
- **Infraestrutura QML Existente:** `krita/qmlmodules/components/` (`org.krita.components 1.0`) e `krita/qmlmodules/widgets/` (`KisQQuickWidget`, `KisQQuickPopupWidget`).

---

## 3. Estratégia da Ponte C++ ↔ QML

1. **`KisMainWindow` em Modo Tablet Shell:** preserva a instância de `KisMainWindow` e `KisViewManager` (mantendo compatibilidade com JNI e `KisTouchGestureAction`), mas oculta por padrão no Android a barra de menus, barras de ferramentas e dockers fixos, expandindo `KisView` / `KisOpenGLCanvas2` para tela cheia.
2. **Superfícies Flutuantes Restritas às Bordas:** em vez de cobrir `KisOpenGLCanvas2` com um único `QQuickWidget` transparente em tela cheia (o que interceptaria `QTabletEvent`/`QTouchEvent` e reduziria o FPS pela metade), os controles flutuantes permanentes ocupam apenas suas pequenas geometrias nas bordas/cantos, deixando >92% da superfície OpenGL livre para entrada direta de stylus e gestos.
3. **Popovers sob Demanda (`KisQQuickPopupWidget`):** os 4 popovers (**Pincéis**, **Cores**, **Camadas**, **Ferramentas**) usam janelas `Qt::Popup | Qt::FramelessWindowHint` empacotadas em `qrc:/` dentro de `kritatabletui` (`lib_kritatabletui.so`).
4. **Adaptadores C++ (`QObject`):** `KisTabletCanvasBridge`, `KisTabletBrushBridge`, `KisTabletColorBridge` e `KisTabletLayerBridge` expõem propriedades reativas (`Q_PROPERTY` com `KisSignalCompressor`) e comandos (`Q_INVOKABLE`) diretamente sobre os serviços de `libs/ui`.
