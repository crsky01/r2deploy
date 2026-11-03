#!/bin/bash
# z2ios / k2ios 一键部署脚本（在服务器上执行）
set -e
log() { echo "[$(date '+%H:%M:%S')] $*"; }

REPO="https://raw.githubusercontent.com/crsky01/r2deploy/main"

cd /root/r2ios/deploy

log "下载最新部署文件..."
curl -fsSL "$REPO/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$REPO/Caddyfile" -o Caddyfile
curl -fsSL "$REPO/01-schema.sql" -o init/01-schema.sql

log "复制源码..."
[ -d /root/z2ios ] || cp -a /root/r2ios /root/z2ios
[ -d /root/k2ios ] || cp -a /root/r2ios /root/k2ios

log "品牌改名..."
find /root/z2ios/src -type f \( -name '*.ts' -o -name '*.tsx' \) -exec sed -i 's/r2ios/z2ios/g; s/R2IOS/Z2IOS/g' {} +
find /root/k2ios/src -type f \( -name '*.ts' -o -name '*.tsx' \) -exec sed -i 's/r2ios/k2ios/g; s/R2IOS/K2IOS/g' {} +

log "生成密钥..."
eval "$(python3 - <<'PYEOF'
import secrets, hmac, hashlib, base64, json, time, string
def b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode()
def anon(secret):
    h = b64(json.dumps({"alg":"HS256","typ":"JWT"}).encode())
    p = b64(json.dumps({"role":"authenticator","iss":"zk","iat":int(time.time()),"exp":int(time.time())+100*365*86400}).encode())
    s = b64(hmac.new(secret.encode(), f"{h}.{p}".encode(), hashlib.sha256).digest())
    return f"{h}.{p}.{s}"
A = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
PW = string.ascii_letters + string.digits + "@"
out = []
for pre in ("Z2","K2"):
    jwt = secrets.token_hex(32)
    out.append(f"{pre}_JWT_SECRET='{jwt}'")
    out.append(f"{pre}_ANON_KEY='{anon(jwt)}'")
    pw = "".join(secrets.choice(PW) for _ in range(12))
    out.append(f"{pre}_ADMIN_PASSWORD='{pw}'")
    totp = "".join(secrets.choice(A) for _ in range(16))
    out.append(f"{pre}_ADMIN_TOTP_SECRET='{totp}'")
print("\n".join(out))
PYEOF
)"

log "写入 .env..."
cat >> .env <<ENVEOF
Z2_JWT_SECRET=$Z2_JWT_SECRET
Z2_ANON_KEY=$Z2_ANON_KEY
Z2_ADMIN_PASSWORD=$Z2_ADMIN_PASSWORD
Z2_ADMIN_TOTP_SECRET=$Z2_ADMIN_TOTP_SECRET
K2_JWT_SECRET=$K2_JWT_SECRET
K2_ANON_KEY=$K2_ANON_KEY
K2_ADMIN_PASSWORD=$K2_ADMIN_PASSWORD
K2_ADMIN_TOTP_SECRET=$K2_ADMIN_TOTP_SECRET
ENVEOF

log "创建数据库..."
AUTH_PW=$(grep '^AUTHENTICATOR_PASSWORD=' .env | cut -d= -f2-)
docker compose exec -T db psql -U postgres -c "CREATE DATABASE z2ios;" || true
docker compose exec -T db psql -U postgres -c "CREATE DATABASE k2ios;" || true
docker compose exec -T db psql -U postgres -d z2ios -v auth_password="$AUTH_PW" -f - < init/01-schema.sql
docker compose exec -T db psql -U postgres -d k2ios -v auth_password="$AUTH_PW" -f - < init/01-schema.sql

log "构建启动（后台，约5-10分钟）..."
nohup docker compose up -d --build > /root/zk-build.log 2>&1 &

{
  echo "z2ios admin: $Z2_ADMIN_PASSWORD  TOTP: $Z2_ADMIN_TOTP_SECRET"
  echo "k2ios admin: $K2_ADMIN_PASSWORD  TOTP: $K2_ADMIN_TOTP_SECRET"
} > /root/zk-credentials.txt

log "部署已启动。管理员凭据如下（同时已保存到 /root/zk-credentials.txt）："
echo "Z2IOS admin密码: $Z2_ADMIN_PASSWORD"
echo "Z2IOS TOTP密钥: $Z2_ADMIN_TOTP_SECRET"
echo "K2IOS admin密码: $K2_ADMIN_PASSWORD"
echo "K2IOS TOTP密钥: $K2_ADMIN_TOTP_SECRET"
echo "构建日志: /root/zk-build.log"
