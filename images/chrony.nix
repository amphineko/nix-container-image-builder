{ pkgs }:
let
  files = pkgs.runCommand "chrony-files" {} ''
    mkdir -p "$out/etc"
    cp ${./chrony/chrony.conf} "$out/etc/chrony.conf"
    cat > "$out/etc/passwd" <<'EOF'
    root:x:0:0:root:/root:/sbin/nologin
    chrony:x:65532:65532:chrony:/var/lib/chrony:/sbin/nologin
    EOF
    cat > "$out/etc/group" <<'EOF'
    root:x:0:
    chrony:x:65532:
    EOF
  '';
in {
  name = "chrony";
  tag = pkgs.chrony.version;
  contents = [ pkgs.chrony pkgs.cacert files ];

  extraCommands = ''
    mkdir -p run/chrony var/lib/chrony tmp
    chmod 1777 tmp
  '';
  fakeRootCommands = ''
    chown 65532:65532 run/chrony var/lib/chrony
    chmod 0750 run/chrony var/lib/chrony
  '';

  config = {
    User = "65532:65532";
    Entrypoint = [ "${pkgs.chrony}/bin/chronyd" ];
    Cmd = [ "-d" "-x" "-U" "-u" "chrony" "-f" "/etc/chrony.conf" ];
    Env = [
      "PATH=/bin:/sbin"
      "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
    ];
    ExposedPorts = { "123/udp" = {}; };
    Labels = {
      "org.opencontainers.image.title" = "chrony";
      "org.opencontainers.image.version" = pkgs.chrony.version;
      "org.opencontainers.image.description" = "NTP server built with Nix; system clock control disabled by default";
    };
  };
}
