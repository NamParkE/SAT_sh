#!/bin/bash
# 서버 접속 관리 시스템 - 에이전트 설치 스크립트
# 토큰 없이 관리 서버 URL만으로 자동 등록

set -e

# apt-get 설치 시 상호작용 프롬프트 무시 (debconf 경고 방지)
export DEBIAN_FRONTEND=noninteractive

echo "============================================"
echo "  서버 접속 관리 시스템 - 에이전트 설치"
echo "============================================"

if [ -z "$1" ]; then
    echo "사용법: ./install.sh <관리서버URL> [표시이름]"
    echo "예시:   ./install.sh http://192.168.1.100:8000"
    echo "예시:   ./install.sh http://192.168.1.100:8000 '웹서버-01'"
    exit 1
fi

SERVER_URL="$1"
DISPLAY_NAME="${2:-}"
INSTALL_DIR="/opt/server-agent"

# Python 확인 및 설치
if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null || ! python3 -c "import ensurepip" &> /dev/null; then
    echo "[1/4] Python3, pip3 및 venv 설치 중..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update -yq
        sudo apt-get install -y python3 python3-pip python3-venv
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3 python3-pip
    else
        echo "[오류] Python3, pip3 및 venv를 수동으로 설치하세요."
        exit 1
    fi
fi

echo "[1/4] 설치 디렉토리 생성..."
sudo mkdir -p "$INSTALL_DIR"
echo "[1.5/4] 에이전트 스크립트 다운로드..."
sudo curl -sSL "$SERVER_URL/agent/agent-script" -o "$INSTALL_DIR/agent.py"

echo "[2/4] Python 패키지 설치..."
# PEP 668(externally-managed-environment) 대응을 위해 가상환경(venv) 생성 및 설치
sudo python3 -m venv "$INSTALL_DIR/venv"
sudo "$INSTALL_DIR/venv/bin/pip" install websockets paramiko psutil --quiet

echo "[3/4] 설정 파일 생성..."
sudo tee "$INSTALL_DIR/config.env" > /dev/null << EOF
SERVER_URL=${SERVER_URL}
DISPLAY_NAME=${DISPLAY_NAME}
EOF

echo "[4/4] systemd 서비스 등록..."
sudo tee /etc/systemd/system/server-agent.service > /dev/null << EOF
[Unit]
Description=서버 접속 관리 에이전트
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
EnvironmentFile=${INSTALL_DIR}/config.env
ExecStart=${INSTALL_DIR}/venv/bin/python ${INSTALL_DIR}/agent.py --server \${SERVER_URL} --name "\${DISPLAY_NAME}"
Restart=always
RestartSec=15
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable server-agent
sudo systemctl restart server-agent

echo ""
echo "============================================"
echo "  에이전트 설치 완료!"
echo "  관리 서버: ${SERVER_URL}"
echo ""
echo "  상태 확인: sudo systemctl status server-agent"
echo "  로그 확인: sudo journalctl -u server-agent -f"
echo ""
echo "  에이전트가 관리 서버에 자동 등록됩니다."
echo "  클라이언트에서 새로고침하면 이 서버가 나타납니다."
echo "============================================"
