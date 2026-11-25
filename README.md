# Bloc Viewer – DevTools extension

Shows every live `Cubit`/`Bloc` of a running Flutter app as a persistent tree.
Changed values flash amber, new nodes green, removed nodes flash their parent
red. Double-tap a leaf value to edit it in the running app.

```
packages/
  bloc_viewer/                    app-side package (BlocViewer.install, observer)
    extension/devtools/           config.yaml + build/ (compiled extension)
  bloc_viewer_devtools_extension/ the Flutter web app = the extension UI
  bloc_viewer_example/            demo app with Cubits, a Bloc and dynamic cubits
tool/setup.sh                     one-time: flutter create + pub get
tool/build_extension.sh           build_and_copy + validate
.run/                             IntelliJ run configurations
```

## First time
1. `tool/setup.sh`
2. Open this folder in IntelliJ IDEA (Flutter + Dart plugins). If the packages are not
   recognised: Settings → Languages & Frameworks → Dart → enable for the project.

## Develop the UI (fast loop, hot restart)
1. Run the example app (run config **Example app**, any device) and copy the
   VM service URI from the console (`http://127.0.0.1:xxxxx/...`).
2. Run **Extension (simulated DevTools)** on **Chrome** (pick Chrome in the device selector).
3. Paste the VM service URI into the simulated environment's connect field.

## Try it inside the real DevTools
1. Run **Build extension into package** (or `tool/build_extension.sh`).
2. Run the example app, open DevTools (IntelliJ: Flutter Inspector → "Open DevTools").
3. Enable the extension via the **Extensions** button (top right); a **bloc_viewer** tab appears.
   After rebuilding the extension, restart DevTools / reload the tab.

## Using it in your own app
```yaml
dev_dependencies:   # or dependencies
  bloc_viewer:
    path: /Users/oliversass/stash/private/flutter/bloc_viewer/packages/bloc_viewer
```
```dart
void main() {
  BlocViewer.install();                       // before any bloc is created
  BlocViewer.registerDecoder<MyState>(MyState.fromJson); // optional: enables editing
  runApp(const MyApp());
}
```
Already have a `BlocObserver`? `BlocViewer.install(delegate: MyObserver())`.

### Editing rules
* States that are `int`/`double`/`bool`/`String` are editable out of the box.
* Object states need `toJson()` (or `BlocViewer.registerEncoder<T>`) to be displayed as fields
  and a registered decoder (`fromJson`) to be editable. The edited JSON is decoded into a new
  state and `emit`ted, so the app reacts exactly as to a normal state change.
* Without `toJson()`, states are shown via `toString()` (or Equatable `props`), read-only.
