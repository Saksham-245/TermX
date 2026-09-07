{
  "targets": [
    {
      "target_name": "native_window",
      "sources": [
        "native-window.cc"
      ],
      "include_dirs": [
        "<!@(node -p \"require('node-addon-api').include\")"
      ],
      "defines": [
        "NAPI_CPP_EXCEPTIONS"
      ],
      "cflags!": [
        "-fno-exceptions"
      ],
      "cflags_cc!": [
        "-fno-exceptions"
      ],
      "cflags_cc": [
        "-std=c++17",
        "-fexceptions"
      ],
      "libraries": [
        "-lX11"
      ]
    }
  ]
}