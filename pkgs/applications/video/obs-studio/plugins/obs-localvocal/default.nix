{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  obs-studio,
  qtbase,
  openblas,
  icu,
  curl,
  onnxruntime,
  whisper-cpp,
  ctranslate2,
  sentencepiece,
}:

# obs-localvocal normally vendors (via FetchContent/ExternalProject) Whisper.cpp,
# CTranslate2, sentencepiece, ICU, libcurl and ONNX Runtime, and builds a Rust
# (Corrosion) crate for WebVTT embedding. FetchContent/ExternalProject need network
# access at build time, which Nix forbids, so every dependency that nixpkgs already
# packages is pulled in through the upstream USE_SYSTEM_* switches instead, and the
# optional WebVTT embedding (the only remaining network/vendored piece) is disabled.
stdenv.mkDerivation (finalAttrs: {
  pname = "obs-localvocal";
  version = "0.6.2";

  # The 0.6.2 release tag predates the pkg-config OpenBLAS detection fix needed to
  # find nixpkgs' openblas (da48778, "fix: prefer pkg-config for OpenBLAS detection"),
  # so build the 4 commits past the tag instead.
  src = fetchFromGitHub {
    owner = "royshil";
    repo = "obs-localvocal";
    rev = "da487783e6d37f927b0fa576fd23dcf7962fe429";
    hash = "sha256-Y6j0GCeavyOoQdVS7KFiL65sFgqu2OnbmeSfCHV0Osk=";
  };

  # Used by cmake/linux/defaults.cmake and BuildWhispercpp.cmake to select the
  # default CPU backend ("generic"); also emitted into CPack filenames.
  ACCELERATION = "generic";

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];

  buildInputs = [
    obs-studio
    qtbase
    openblas
    icu
    curl
    onnxruntime
    whisper-cpp
    ctranslate2
    sentencepiece
  ];

  cmakeFlags = [
    "-DUSE_SYSTEM_CURL=ON"
    "-DUSE_SYSTEM_ICU=ON"
    "-DUSE_SYSTEM_ONNXRUNTIME=ON"
    "-DUSE_SYSTEM_WHISPERCPP=ON"
    "-DUSE_SYSTEM_CTRANSLATE2=ON"
    "-DUSE_SYSTEM_SENTENCEPIECE=ON"
    # Avoids the network-fetching Rust/Corrosion WebVTT build.
    "-DENABLE_WEBVTT=OFF"
    # nixpkgs sets this ON by default, but the plugin's own compilerconfig.cmake
    # enables -Wunused-parameter and upstream leaks one in
    # transcription-filter-callbacks.cpp (possible_end_ts), which under -Werror
    # breaks the build.
    (lib.cmakeBool "CMAKE_COMPILE_WARNING_AS_ERROR" false)
    # nixpkgs' onnxruntime ships a CMake config that only exports a target, it does
    # not populate the old-style Onnxruntime_LIBRARIES/INCLUDE_DIR variables that the
    # USE_SYSTEM_ONNXRUNTIME block reads, so provide them explicitly.
    "-DOnnxruntime_INCLUDE_DIR=${onnxruntime}/include"
    "-DOnnxruntime_LIBRARIES=${onnxruntime}/lib/libonnxruntime.so"
  ];

  dontWrapQtApps = true;

  meta = {
    homepage = "https://github.com/locaal-ai/obs-localvocal";
    changelog = "https://github.com/locaal-ai/obs-localvocal/releases";
    description = "OBS plugin for local, private, real-time speech recognition (captioning and translation) using AI";
    longDescription = ''
      Real-time, local speech-to-text and translation for OBS Studio using
      Whisper.cpp, Silero VAD and CTranslate2. Runs fully offline - no audio
      ever leaves the machine.
    '';
    license = lib.licenses.gpl2Only;
    maintainers = with lib.maintainers; [ ];
    inherit (obs-studio.meta) platforms;
  };
})