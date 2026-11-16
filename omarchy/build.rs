use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    let qml = [
        "qml/Main.qml",
        "qml/BrowserTab.qml",
        "qml/TabStrip.qml",
        "qml/Sidebar.qml",
        "qml/Omnibox.qml",
        "qml/FindBar.qml",
        "qml/StartPage.qml",
    ];
    let mut module = QmlModule::new("app.omaweb");
    for f in qml {
        module = module.qml_file(f);
    }
    CxxQtBuilder::new_qml_module(module)
        .qt_module("Network")
        .qt_module("Quick")
        .qt_module("WebEngineQuick")
        .include_dir("cpp")
        .cpp_file("cpp/platform.cpp")
        .files(["src/bridge.rs"])
        .build();
}
