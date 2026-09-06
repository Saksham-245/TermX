{
  "targets": [
    {
      "target_name": "native_window",
      "sources": ["native-bridge.cc"],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")"
      ],
      "defines": ["NAPI_DISABLE_CPP_EXCEPTIONS"],
      "libraries": [
        "<(module_root_dir)/lib/libTermXWindow.dylib"
      ],
      "xcode_settings": {
        "CLANG_CXX_LANGUAGE_STANDARD": "c++17",
        "MACOSX_DEPLOYMENT_TARGET": "26.0"
      }
    }
  ]
}