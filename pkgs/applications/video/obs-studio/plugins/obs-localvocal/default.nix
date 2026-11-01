{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  cmake,
  ninja,
  pkg-config,
  obs-studio,
  qtbase,
  openblas,
  icu,
  curl,
  whisper-cpp,
  whisper-cpp-vulkan,
  ctranslate2,
  sentencepiece,
  vulkan-loader,
  acceleration ? "nvidia",
}:

# obs-localvocal normally vendors (via FetchContent/ExternalProject) Whisper.cpp,
# CTranslate2, sentencepiece, ICU, libcurl and ONNX Runtime, and builds a Rust
# (Corrosion) crate for WebVTT embedding. FetchContent/ExternalProject need network
# access at build time, which Nix forbids, so every dependency that nixpkgs already
# packages is pulled in through the upstream USE_SYSTEM_* switches instead, and the
# optional WebVTT embedding (the only remaining network/vendored piece) is disabled.

let
  nvidiaAccel = acceleration == "nvidia";
  # With USE_SYSTEM_WHISPERCPP the plugin links nixpkgs' whisper-cpp directly, so the
  # accelerator really comes from that package. For "nvidia" we link the Vulkan build
  # (works on NVIDIA GPUs through Vulkan) - the CUDA build of whisper.cpp is far too
  # slow and pulls in the whole CUDA toolkit, so Vulkan is preferred.
  whisper = if nvidiaAccel then whisper-cpp-vulkan else whisper-cpp;

  # The plugin expects onnxruntime for the Silero VAD. The nixpkgs build of onnxruntime
  # dynamically links an external libprotobuf-lite, which is fragile when loaded inside
  # OBS (the shared protobuf can be interposed by other libs in the process, yielding
  # "Protobuf parsing failed" / ORT_INVALID_PROTOBUF on model load). The upstream releases
  # statically link their protobuf and are what obs-localvocal is tested against, so use
  # the self-contained 1.20.1 CPU tarball (fed to the plugin via its built-in
  # CUSTOM_ONNXRUNTIME_URL/HASH override, avoiding any network fetch during the build).
  onnxruntime-src = fetchurl {
    url = "https://github.com/microsoft/onnxruntime/releases/download/v1.20.1/onnxruntime-linux-x64-1.20.1.tgz";
    sha256 = "01d1l70vmaq3l22ymixg96cgh7k05k47b5b15va3y7hzav0lvnv7";
  };
in
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

  # Upstream lets an Ort::Exception escape from Silero VAD initialization, which
  # on a model-load failure terminates the whole OBS process (uncaught exception ->
  # std::terminate -> SIGABRT). Catch it, log the real onnxruntime error, and disable
  # the filter instead of crashing.
  patches = [ ./crash-safety.patch ];

  # Used by cmake/linux/defaults.cmake and BuildWhispercpp.cmake to select the
  # acceleration backend (also emitted into CPack filenames).
  ACCELERATION = acceleration;

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
    whisper
    ctranslate2
    sentencepiece
  ]
  ++ lib.optionals nvidiaAccel [
    vulkan-loader
  ];

  cmakeFlags = [
    "-DUSE_SYSTEM_CURL=ON"
    "-DUSE_SYSTEM_ICU=ON"
    "-DUSE_SYSTEM_WHISPERCPP=ON"
    "-DUSE_SYSTEM_CTRANSLATE2=ON"
    "-DUSE_SYSTEM_SENTENCEPIECE=ON"
    # Self-contained onnxruntime 1.20.1 (see the comment above on onnxruntime-src). The
    # plugin's FetchOnnxruntime.cmake tunes off the system path and uses our tarball via
    # a local file:// URL, so no network is needed at build time.
    "-DUSE_SYSTEM_ONNXRUNTIME=OFF"
    "-DCUSTOM_ONNXRUNTIME_URL=file://${onnxruntime-src}"
    "-DCUSTOM_ONNXRUNTIME_HASH=SHA256=67db4dc1561f1e3fd42e619575c82c601ef89849afc7ea85a003abbac1a1a105"
    # Avoids the network-fetching Rust/Corrosion WebVTT build.
    "-DENABLE_WEBVTT=OFF"
    # nixpkgs sets this ON by default, but the plugin's own compilerconfig.cmake
    # enables -Wunused-parameter and upstream leaks one in
    # transcription-filter-callbacks.cpp (possible_end_ts), which under -Werror
    # breaks the build.
    (lib.cmakeBool "CMAKE_COMPILE_WARNING_AS_ERROR" false)
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

      When built with acceleration = "nvidia" (the default), the Vulkan
      Whisper.cpp backend is enabled so transcription runs on a compatible
      GPU (works on NVIDIA hardware through Vulkan). Use acceleration =
      "generic" for a CPU-only build.
    '';
    license = lib.licenses.gpl2Only;
    maintainers = with lib.maintainers; [ ];
    inherit (obs-studio.meta) platforms;
  };
})