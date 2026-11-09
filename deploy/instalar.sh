#!/usr/bin/env bash
# Instala el proyecto #32 en Ubuntu 24.04 (AWS EC2 ARM o x86) y lo deja como servicio systemd.
# Uso:  git clone <repo> && cd <repo> && bash deploy/instalar.sh
set -euo pipefail
cd "$(dirname "$0")/.."
REL=p32_linea_de_produccion
DEST=/opt/linea32

echo "==[1/5] Instalando Erlang/OTP y rebar3 con apt =="
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  erlang-base erlang-dev erlang-eunit erlang-inets erlang-ssl erlang-crypto erlang-public-key \
  erlang-asn1 erlang-os-mon erlang-parsetools erlang-syntax-tools erlang-tools erlang-xmerl \
  erlang-edoc rebar3 git curl
erl -noshell -eval 'io:format("OTP ~s~n",[erlang:system_info(otp_release)]), halt().'

echo "==[2/5] Compilando (warnings_as_errors) =="
rebar3 compile

echo "==[3/5] Pruebas eunit (incluye pruebas de caos) =="
rebar3 eunit

echo "==[4/5] Armando el release =="
rebar3 release

echo "==[5/5] Instalando como servicio systemd =="
sudo systemctl stop linea32 2>/dev/null || true
id linea32 >/dev/null 2>&1 || sudo useradd --system --home "$DEST" --shell /usr/sbin/nologin linea32
sudo rm -rf "$DEST" && sudo mkdir -p "$DEST"
sudo cp -r "_build/default/rel/$REL/." "$DEST/"
sudo mkdir -p "$DEST/tmp"
sudo chown -R linea32:linea32 "$DEST"
sudo tee /etc/systemd/system/linea32.service >/dev/null <<UNIT
[Unit]
Description=Linea de produccion #32 (Erlang/OTP)
After=network.target

[Service]
User=linea32
Environment=HOME=$DEST
Environment=RELX_OUT_FILE_PATH=$DEST/tmp
ExecStart=$DEST/bin/$REL foreground
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable --now linea32
sleep 4

TOKEN=$(curl -s -m 2 -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' || true)
IP=$(curl -s -m 2 -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4 || echo "TU_IP_PUBLICA")
echo
echo "LISTO. Abre en tu navegador: http://$IP:8080"
