{ lib
, stdenv
, fetchurl
, jre
, autoPatchelfHook
, zlib
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "sbt";
  version = "1.9.0";

  src = fetchurl {
    url = "https://github.com/sbt/sbt/releases/download/v${finalAttrs.version}/sbt-${finalAttrs.version}.tgz";
    hash = "sha256-zFWTSOr5z75s4i9omx5EDI4FtOSc1r6jmHZHd7N5SMQ=";
  };

  postPatch = ''
    echo -java-home ${jre.home} >>conf/sbtopts
  '';

  nativeBuildInputs = lib.optionals stdenv.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.isLinux [
    stdenv.cc.cc # libstdc++.so.6
    zlib
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/sbt $out/bin
    cp -ra . $out/share/sbt
    ln -sT ../share/sbt/bin/sbt $out/bin/sbt
    ln -sT ../share/sbt/bin/sbtn-x86_64-${
      if (stdenv.isDarwin) then "apple-darwin" else "pc-linux"
    } $out/bin/sbtn

    runHook postInstall
  '';

  meta = with lib; {
    homepage = "https://www.scala-sbt.org/";
    license = licenses.bsd3;
    sourceProvenance = with sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
    description = "A build tool for Scala, Java and more";
    maintainers = with maintainers; [ nequissimus ];
    platforms = platforms.unix;
  };
})
