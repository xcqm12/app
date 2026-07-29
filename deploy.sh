#!/bin/bash
# ============================================================================
# BBSMC 一键部署脚本 (宝塔 Ubuntu 8H8G)
# 项目: https://github.com/xcqm12/app
# 组件: Labrinth(Rust API) + Nuxt3 前端 + PostgreSQL/Redis/Meilisearch/ClickHouse
# ============================================================================
set -eo pipefail

# ---------------------- 安全初始化: 所有可选变量默认值 ----------------------
# 防止 set -u (或用户环境中 set -u) 导致 unbound variable 错误
: "${DOMAIN:=}"
: "${API_SUBDOMAIN:=api}"
: "${CDN_SUBDOMAIN:=cdn}"
: "${INSTALL_DIR:=/www/wwwroot/bbsmc}"
: "${DATA_DIR:=/www/wwwroot/bbsmc-data}"
: "${REPO_URL:=https://github.com/xcqm12/app.git}"
: "${REPO_BRANCH:=main}"
: "${AUTO_ACCEPT:=0}"
: "${SKIP_BUILD_PREPARE:=0}"
: "${MIRROR_MODE:=0}"
: "${MIRROR_INPUT:=}"
: "${THIRD_PARTY_INPUT:=}"
: "${PAY_INPUT:=}"
: "${CONFIRM:=}"
: "${INPUT:=}"
: "${CPU_CORES:=}"
: "${TOTAL_MEM:=}"

# 数据库/加密密码
: "${PG_PASS:=}"
: "${MEILI_KEY:=}"
: "${REDIS_PASS:=}"
: "${CH_PASS:=}"
: "${ADMIN_KEY:=}"
: "${ENCRYPTION_KEY:=}"

# OAuth 配置
: "${GITHUB_CLIENT_ID:=}"
: "${GITHUB_CLIENT_SECRET:=}"
: "${MICROSOFT_CLIENT_ID:=}"
: "${MICROSOFT_CLIENT_SECRET:=}"
: "${GITLAB_CLIENT_ID:=}"
: "${GITLAB_CLIENT_SECRET:=}"
: "${DISCORD_CLIENT_ID:=}"
: "${DISCORD_CLIENT_SECRET:=}"
: "${GOOGLE_CLIENT_ID:=}"
: "${GOOGLE_CLIENT_SECRET:=}"
: "${BILIBILI_CLIENT_ID:=}"
: "${BILIBILI_CLIENT_SECRET:=}"
: "${QQ_CLIENT_ID:=}"
: "${QQ_CLIENT_SECRET:=}"

# SMTP 配置
: "${SMTP_HOST:=}"
: "${SMTP_USERNAME:=}"
: "${SMTP_PASSWORD:=}"

# 支付配置
: "${PAYPAL_CLIENT_ID:=}"
: "${PAYPAL_CLIENT_SECRET:=}"
: "${STRIPE_API_KEY:=}"
: "${STRIPE_WEBHOOK_SECRET:=}"

# ---------------------- 颜色输出 ----------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}=====> $* <=====${NC}"; }

# ---------------------- 默认配置 ----------------------
# 会被用户输入或环境变量覆盖 (顶部已通过 : "${VAR:=}" 初始化)

# 数据库密码（自动生成或从已有凭据恢复）
CREDENTIALS_FILE="${INSTALL_DIR}/deploy-credentials.txt"

# 如果已有凭据文件, 从中提取密码 (避免重新部署时密码变更导致认证失败)
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    info "检测到已有凭据文件, 从 ${CREDENTIALS_FILE} 恢复密码..."
    [[ -z "${PG_PASS}" ]] && PG_PASS=$(grep 'PostgreSQL:' "${CREDENTIALS_FILE}" 2>/dev/null | head -1 | sed -n 's/.*PostgreSQL:[[:space:]]*labrinth:\([^@]*\)@.*/\1/p') || true
    [[ -z "${MEILI_KEY}" ]] && MEILI_KEY=$(grep 'Meilisearch:' "${CREDENTIALS_FILE}" 2>/dev/null | sed -n 's/.*Key:[[:space:]]*\(\S*\).*/\1/p') || true
    [[ -z "${REDIS_PASS}" ]] && REDIS_PASS=$(grep 'Redis:' "${CREDENTIALS_FILE}" 2>/dev/null | sed -n 's/.*密码:[[:space:]]*\([^)]*\).*/\1/p') || true
    [[ -z "${CH_PASS}" ]] && CH_PASS=$(grep 'ClickHouse:' "${CREDENTIALS_FILE}" 2>/dev/null | sed -n 's/.*default\/\(\S*\).*/\1/p') || true
    [[ -z "${ADMIN_KEY}" ]] && ADMIN_KEY=$(grep 'Labrinth Admin Key:' "${CREDENTIALS_FILE}" 2>/dev/null | awk -F': *' '{print $2}') || true
    [[ -z "${ENCRYPTION_KEY}" ]] && ENCRYPTION_KEY=$(grep 'Encryption Key:' "${CREDENTIALS_FILE}" 2>/dev/null | awk -F': *' '{print $2}') || true

    # 恢复域名配置
    [[ -z "${DOMAIN}" ]] && DOMAIN=$(grep '主域名:' "${CREDENTIALS_FILE}" 2>/dev/null | sed 's/.*主域名:[[:space:]]*//') || true

    # 验证是否全部恢复成功
    if [[ -n "${PG_PASS}" ]] && [[ -n "${MEILI_KEY}" ]] && [[ -n "${ADMIN_KEY}" ]]; then
        info "密码恢复成功"
    else
        warn "部分密码未能从凭据文件恢复, 将重新生成 (可能导致数据库认证失败)"
    fi
fi

# 从已有 .env 恢复域名和第三方配置 (优先级: 环境变量 > .env > 默认)
load_existing_config() {
    local env_file="${INSTALL_DIR}/apps/labrinth/.env"
    [[ ! -f "${env_file}" ]] && env_file="${INSTALL_DIR}/bin/.env"
    [[ ! -f "${env_file}" ]] && return 0

    info "检测到已有配置文件, 恢复设置..."

    # 读取配置值的辅助函数
    get_env() {
        grep "^$1=" "${env_file}" 2>/dev/null | head -1 | cut -d= -f2-
    }

    # 域名
    local site_url self_addr cdn_url
    site_url=$(get_env "SITE_URL" | sed 's/https\?:\/\///' | sed 's/\/.*//')
    self_addr=$(get_env "SELF_ADDR" | sed 's/https\?:\/\///' | sed 's/\/.*//')
    cdn_url=$(get_env "CDN_URL" | sed 's/https\?:\/\///' | sed 's/\/.*//')

    if [[ -z "${DOMAIN}" ]] && [[ -n "${site_url}" ]]; then
        DOMAIN="${site_url}"
        info "  主域名: ${DOMAIN}"
    fi
    if [[ -n "${self_addr}" ]] && [[ "${self_addr}" == api.* ]]; then
        API_SUBDOMAIN="${self_addr%%.*}"
        # 检查 self_addr 的主域名是否与 DOMAIN 一致
        local self_main_domain
        self_main_domain=$(echo "${self_addr}" | cut -d. -f2-)
        if [[ -n "${DOMAIN}" ]] && [[ "${self_main_domain}" != "${DOMAIN}" ]]; then
            warn "  SELF_ADDR 主域名 (${self_main_domain}) 与 DOMAIN (${DOMAIN}) 不一致, 已忽略"
            API_SUBDOMAIN="api"
        fi
    fi
    if [[ -n "${cdn_url}" ]] && [[ "${cdn_url}" == cdn.* ]]; then
        CDN_SUBDOMAIN="${cdn_url%%.*}"
    fi

    # OAuth 配置 (仅当未通过环境变量设置时恢复)
    for provider in GITHUB MICROSOFT GITLAB DISCORD GOOGLE BILIBILI QQ; do
        local id_var="${provider}_CLIENT_ID"
        local secret_var="${provider}_CLIENT_SECRET"
        if [[ -z "${!id_var:-}" ]] || [[ "${!id_var:-}" == "none" ]]; then
            local val
            val=$(get_env "${id_var}")
            [[ -n "${val}" ]] && declare "${id_var}=${val}"
        fi
        if [[ -z "${!secret_var:-}" ]] || [[ "${!secret_var:-}" == "none" ]]; then
            local val
            val=$(get_env "${secret_var}")
            [[ -n "${val}" ]] && declare "${secret_var}=${val}"
        fi
    done

    # SMTP 配置
    if [[ -z "${SMTP_HOST}" ]] || [[ "${SMTP_HOST}" == "none" ]]; then
        SMTP_HOST=$(get_env "SMTP_HOST")
        [[ -n "${SMTP_HOST}" ]] && info "  SMTP: ${SMTP_HOST}"
    fi
    if [[ -z "${SMTP_USERNAME}" ]] || [[ "${SMTP_USERNAME}" == "none" ]]; then
        SMTP_USERNAME=$(get_env "SMTP_USERNAME")
    fi
    if [[ -z "${SMTP_PASSWORD}" ]] || [[ "${SMTP_PASSWORD}" == "none" ]]; then
        SMTP_PASSWORD=$(get_env "SMTP_PASSWORD")
    fi

    # 支付配置
    if [[ -z "${PAYPAL_CLIENT_ID}" ]] || [[ "${PAYPAL_CLIENT_ID}" == "none" ]]; then
        PAYPAL_CLIENT_ID=$(get_env "PAYPAL_CLIENT_ID")
    fi
    if [[ -z "${PAYPAL_CLIENT_SECRET}" ]] || [[ "${PAYPAL_CLIENT_SECRET}" == "none" ]]; then
        PAYPAL_CLIENT_SECRET=$(get_env "PAYPAL_CLIENT_SECRET")
    fi
    if [[ -z "${STRIPE_API_KEY}" ]] || [[ "${STRIPE_API_KEY}" == "none" ]]; then
        STRIPE_API_KEY=$(get_env "STRIPE_API_KEY")
    fi
    if [[ -z "${STRIPE_WEBHOOK_SECRET}" ]] || [[ "${STRIPE_WEBHOOK_SECRET}" == "none" ]]; then
        STRIPE_WEBHOOK_SECRET=$(get_env "STRIPE_WEBHOOK_SECRET")
    fi

    # 检查是否已配置镜像模式 (通过检测 nginx 配置或特殊标记)
    if [[ -f "/www/server/panel/vhost/nginx/api.${DOMAIN}.conf" ]]; then
        if grep -q "api.modrinth.com" "/www/server/panel/vhost/nginx/api.${DOMAIN}.conf" 2>/dev/null; then
            MIRROR_MODE=1
        fi
    fi
}
load_existing_config

# 对缺失的密码生成随机值
[[ -z "${PG_PASS}" ]] && PG_PASS=$(head -c 16 /dev/urandom | xxd -p)
[[ -z "${MEILI_KEY}" ]] && MEILI_KEY=$(head -c 24 /dev/urandom | base64)
[[ -z "${REDIS_PASS}" ]] && REDIS_PASS=$(head -c 16 /dev/urandom | xxd -p)
[[ -z "${CH_PASS}" ]] && CH_PASS=$(head -c 16 /dev/urandom | xxd -p)
[[ -z "${ADMIN_KEY}" ]] && ADMIN_KEY=$(head -c 24 /dev/urandom | base64)
[[ -z "${ENCRYPTION_KEY}" ]] && ENCRYPTION_KEY=$(head -c 32 /dev/urandom | base64)

# 端口
FRONTEND_PORT=3000
BACKEND_PORT=8000
PG_PORT=5432
REDIS_PORT=6379
MEILI_PORT=7700
CH_PORT=8123

# Modrinth 镜像模式: 1=启用 (GET 代理官网, POST 本地上传), 0=纯本地
MIRROR_MODE="${MIRROR_MODE:-0}"

# ---------------------- OAuth / SMTP / 支付 第三方配置 ----------------------
# 可通过环境变量预置, 或在交互模式下输入
GITHUB_CLIENT_ID="${GITHUB_CLIENT_ID:-none}"
GITHUB_CLIENT_SECRET="${GITHUB_CLIENT_SECRET:-none}"
MICROSOFT_CLIENT_ID="${MICROSOFT_CLIENT_ID:-none}"
MICROSOFT_CLIENT_SECRET="${MICROSOFT_CLIENT_SECRET:-none}"
GITLAB_CLIENT_ID="${GITLAB_CLIENT_ID:-none}"
GITLAB_CLIENT_SECRET="${GITLAB_CLIENT_SECRET:-none}"
DISCORD_CLIENT_ID="${DISCORD_CLIENT_ID:-none}"
DISCORD_CLIENT_SECRET="${DISCORD_CLIENT_SECRET:-none}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-none}"
GOOGLE_CLIENT_SECRET="${GOOGLE_CLIENT_SECRET:-none}"
BILIBILI_CLIENT_ID="${BILIBILI_CLIENT_ID:-none}"
BILIBILI_CLIENT_SECRET="${BILIBILI_CLIENT_SECRET:-none}"
QQ_CLIENT_ID="${QQ_CLIENT_ID:-none}"
QQ_CLIENT_SECRET="${QQ_CLIENT_SECRET:-none}"

SMTP_USERNAME="${SMTP_USERNAME:-none}"
SMTP_PASSWORD="${SMTP_PASSWORD:-none}"
SMTP_HOST="${SMTP_HOST:-none}"

PAYPAL_CLIENT_ID="${PAYPAL_CLIENT_ID:-none}"
PAYPAL_CLIENT_SECRET="${PAYPAL_CLIENT_SECRET:-none}"
STRIPE_API_KEY="${STRIPE_API_KEY:-none}"
STRIPE_WEBHOOK_SECRET="${STRIPE_WEBHOOK_SECRET:-none}"

# ---------------------- 用户输入 ----------------------
collect_input() {
    step "收集部署参数"

    # 标记: 是否所有配置都已恢复 (用于跳过确认)
    local has_existing=0
    [[ -n "${DOMAIN}" ]] && has_existing=1

    # 主域名
    if [[ -z "${DOMAIN}" ]]; then
        read -rp "请输入主域名 (例如: bbsmc.org.cn): " DOMAIN
        [[ -z "${DOMAIN}" ]] && error "域名不能为空"
    else
        info "主域名 (从已有配置恢复): ${DOMAIN}"
        read -rp "  确认或修改 [${DOMAIN}]: " INPUT
        [[ -n "${INPUT}" ]] && DOMAIN="${INPUT}"
    fi

    # 去除可能的协议前缀和路径
    DOMAIN="${DOMAIN#https://}"
    DOMAIN="${DOMAIN#http://}"
    DOMAIN="${DOMAIN%%/*}"
    # 验证域名格式
    if ! echo "${DOMAIN}" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$'; then
        error "域名格式错误: ${DOMAIN}"
    fi

    # API 子域名
    read -rp "API 子域名 [${API_SUBDOMAIN}]: " INPUT
    [[ -n "${INPUT}" ]] && API_SUBDOMAIN="${INPUT}"
    # 如果用户输入的是完整域名 (包含主域名), 自动提取子域名部分
    if echo "${API_SUBDOMAIN}" | grep -qF "${DOMAIN}"; then
        warn "API 子域名包含主域名, 自动提取子域名前缀"
        API_SUBDOMAIN="${API_SUBDOMAIN%.${DOMAIN}}"
    fi

    # CDN 子域名
    read -rp "CDN 子域名 [${CDN_SUBDOMAIN}]: " INPUT
    [[ -n "${INPUT}" ]] && CDN_SUBDOMAIN="${INPUT}"
    if echo "${CDN_SUBDOMAIN}" | grep -qF "${DOMAIN}"; then
        warn "CDN 子域名包含主域名, 自动提取子域名前缀"
        CDN_SUBDOMAIN="${CDN_SUBDOMAIN%.${DOMAIN}}"
    fi

    read -rp "项目安装目录 [${INSTALL_DIR}]: " INPUT
    [[ -n "${INPUT}" ]] && INSTALL_DIR="${INPUT}"
    read -rp "数据存储目录 [${DATA_DIR}]: " INPUT
    [[ -n "${INPUT}" ]] && DATA_DIR="${INPUT}"

    API_DOMAIN="${API_SUBDOMAIN}.${DOMAIN}"
    CDN_DOMAIN="${CDN_SUBDOMAIN}.${DOMAIN}"

    # 是否启用 Modrinth 官网镜像模式
    echo ""
    echo -e "${CYAN}Modrinth 镜像模式说明:${NC}"
    echo "  - 浏览/搜索 GET  -> 代理到 api.modrinth.com (显示官方 mod)"
    echo "  - 上传/修改  POST/PUT/PATCH/DELETE -> 本地 labrinth"
    echo "  - 本地上传不同步到官网, 不修改项目源码"
    local mirror_prompt="[y/N]"
    [[ "${MIRROR_MODE}" == "1" ]] && mirror_prompt="[Y/n]"
    read -rp "是否启用 Modrinth 官网镜像模式? ${mirror_prompt}: " MIRROR_INPUT
    if [[ -n "${MIRROR_INPUT}" ]]; then
        MIRROR_MODE=$([[ "${MIRROR_INPUT}" =~ ^[Yy]$ ]] && echo 1 || echo 0)
    fi

    # ---------- 第三方服务配置 (可选) ----------
    echo ""
    echo -e "${CYAN}第三方服务配置 (可选, 留空跳过):${NC}"
    echo "  配置 OAuth 登录、SMTP 邮件、支付等功能"
    echo "  可部署后随时编辑 apps/labrinth/.env 修改"

    # 检测是否已有第三方配置
    local has_third_party=0
    if [[ -n "${GITHUB_CLIENT_ID}" ]] && [[ "${GITHUB_CLIENT_ID}" != "none" ]]; then
        has_third_party=1
    fi
    if [[ -n "${SMTP_HOST}" ]] && [[ "${SMTP_HOST}" != "none" ]]; then
        has_third_party=1
    fi

    if [[ ${has_third_party} -eq 1 ]]; then
        info "检测到已有第三方配置 (GitHub/SMTP 等)"
        read -rp "是否修改第三方服务配置? [y/N]: " THIRD_PARTY_INPUT
        if [[ "${THIRD_PARTY_INPUT}" =~ ^[Yy]$ ]]; then
            configure_third_party_interactive
        fi
    else
        read -rp "是否现在配置第三方服务? [y/N]: " THIRD_PARTY_INPUT
        if [[ "${THIRD_PARTY_INPUT}" =~ ^[Yy]$ ]]; then
            configure_third_party_interactive
        fi
    fi

    info "部署信息汇总:"
    echo "  主站点:       https://${DOMAIN}"
    echo "  API 服务:     https://${API_DOMAIN}"
    echo "  CDN 域名:     https://${CDN_DOMAIN}"
    echo "  安装目录:     ${INSTALL_DIR}"
    echo "  数据目录:     ${DATA_DIR}"
    local mirror_status="禁用 (纯本地)"
    [[ "${MIRROR_MODE}" == "1" ]] && mirror_status="启用 (代理官网+本地上传)"
    echo "  镜像模式:     ${mirror_status}"

    # 如果已有配置且 AUTO_ACCEPT=1, 自动确认
    if [[ "${AUTO_ACCEPT}" == "1" ]] && [[ ${has_existing} -eq 1 ]]; then
        info "自动确认 (AUTO_ACCEPT=1)"
        return 0
    fi

    read -rp "确认以上信息并继续? [y/N]: " CONFIRM
    [[ "${CONFIRM}" =~ ^[Yy]$ ]] || error "用户取消"
}

# ---------------------- 第三方服务交互配置 ----------------------
configure_third_party_interactive() {
    local callback_base="https://${API_DOMAIN}/auth/callback"

    echo ""
    echo -e "${CYAN}=== OAuth 第三方登录配置 ===${NC}"
    echo "  回调地址基础路径: ${callback_base}"
    echo "  在各平台开发者后台配置回调 URL 时使用此路径"
    echo ""

    # GitHub
    echo -e "${YELLOW}--- GitHub 登录 ---${NC}"
    echo "  开发者后台: https://github.com/settings/developers"
    echo "  回调 URL: ${callback_base}/github"
    read -rp "  GitHub Client ID [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && GITHUB_CLIENT_ID="${INPUT}"
    read -rp "  GitHub Client Secret [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && GITHUB_CLIENT_SECRET="${INPUT}"

    # Microsoft
    echo ""
    echo -e "${YELLOW}--- Microsoft 登录 ---${NC}"
    echo "  开发者后台: https://portal.azure.com -> App registrations"
    echo "  回调 URL: ${callback_base}/microsoft"
    read -rp "  Microsoft Client ID [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && MICROSOFT_CLIENT_ID="${INPUT}"
    read -rp "  Microsoft Client Secret [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && MICROSOFT_CLIENT_SECRET="${INPUT}"

    # GitLab
    echo ""
    echo -e "${YELLOW}--- GitLab 登录 ---${NC}"
    echo "  开发者后台: https://gitlab.com/profile/applications"
    echo "  回调 URL: ${callback_base}/gitlab"
    read -rp "  GitLab Client ID [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && GITLAB_CLIENT_ID="${INPUT}"
    read -rp "  GitLab Client Secret [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && GITLAB_CLIENT_SECRET="${INPUT}"

    # Discord
    echo ""
    echo -e "${YELLOW}--- Discord 登录 ---${NC}"
    echo "  开发者后台: https://discord.com/developers/applications"
    echo "  回调 URL: ${callback_base}/discord"
    read -rp "  Discord Client ID [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && DISCORD_CLIENT_ID="${INPUT}"
    read -rp "  Discord Client Secret [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && DISCORD_CLIENT_SECRET="${INPUT}"

    # Google
    echo ""
    echo -e "${YELLOW}--- Google 登录 ---${NC}"
    echo "  开发者后台: https://console.cloud.google.com/apis/credentials"
    echo "  回调 URL: ${callback_base}/google"
    read -rp "  Google Client ID [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && GOOGLE_CLIENT_ID="${INPUT}"
    read -rp "  Google Client Secret [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && GOOGLE_CLIENT_SECRET="${INPUT}"

    # Bilibili
    echo ""
    echo -e "${YELLOW}--- Bilibili 登录 ---${NC}"
    echo "  开发者后台: https://open.bilibili.com/"
    echo "  回调 URL: ${callback_base}/bilibili"
    read -rp "  Bilibili Client ID [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && BILIBILI_CLIENT_ID="${INPUT}"
    read -rp "  Bilibili Client Secret [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && BILIBILI_CLIENT_SECRET="${INPUT}"

    # QQ
    echo ""
    echo -e "${YELLOW}--- QQ 登录 ---${NC}"
    echo "  开发者后台: https://connect.qq.com/"
    echo "  回调 URL: ${callback_base}/qq"
    read -rp "  QQ Client ID [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && QQ_CLIENT_ID="${INPUT}"
    read -rp "  QQ Client Secret [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && QQ_CLIENT_SECRET="${INPUT}"

    # Gitee 提示
    echo ""
    echo -e "${YELLOW}--- Gitee 登录 ---${NC}"
    echo "  ${RED}注意: Gitee 登录需要修改 Rust 源码添加 Provider${NC}"
    echo "  原生 AuthProvider 枚举不包含 Gitee, 仅修改 .env 无效"
    echo "  需要修改: src/auth/mod.rs + src/routes/internal/flows.rs"
    echo "  参考 GitHub Provider 实现方式添加"

    # SMTP
    echo ""
    echo -e "${CYAN}=== SMTP 邮件配置 ===${NC}"
    echo "  用于邮件验证、密码重置等功能"
    echo "  常见配置:"
    echo "    QQ邮箱:    smtp.qq.com:465"
    echo "    163邮箱:   smtp.163.com:465"
    echo "    Gmail:     smtp.gmail.com:587"
    echo "    Outlook:   smtp.office365.com:587"
    echo "    SendCloud: smtp.sendcloud.net:25"
    read -rp "  SMTP 主机 [留空跳过]: " INPUT
    [[ -n "${INPUT}" ]] && SMTP_HOST="${INPUT}"
    if [[ -n "${SMTP_HOST}" ]]; then
        read -rp "  SMTP 用户名 (邮箱地址): " INPUT
        [[ -n "${INPUT}" ]] && SMTP_USERNAME="${INPUT}"
        read -rp "  SMTP 密码 (授权码): " INPUT
        [[ -n "${INPUT}" ]] && SMTP_PASSWORD="${INPUT}"
    fi

    # 支付
    echo ""
    echo -e "${CYAN}=== 支付配置 ===${NC}"
    echo "  PayPal / Stripe 等支付服务"
    read -rp "  是否配置支付? [y/N]: " PAY_INPUT
    if [[ "${PAY_INPUT}" =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}--- PayPal ---${NC}"
        read -rp "  PayPal Client ID [留空跳过]: " INPUT
        [[ -n "${INPUT}" ]] && PAYPAL_CLIENT_ID="${INPUT}"
        read -rp "  PayPal Client Secret [留空跳过]: " INPUT
        [[ -n "${INPUT}" ]] && PAYPAL_CLIENT_SECRET="${INPUT}"

        echo -e "${YELLOW}--- Stripe ---${NC}"
        read -rp "  Stripe API Key [留空跳过]: " INPUT
        [[ -n "${INPUT}" ]] && STRIPE_API_KEY="${INPUT}"
        read -rp "  Stripe Webhook Secret [留空跳过]: " INPUT
        [[ -n "${INPUT}" ]] && STRIPE_WEBHOOK_SECRET="${INPUT}"
    fi

    # 汇总
    echo ""
    info "第三方配置汇总:"
    local configured=0
    for svc in GitHub Microsoft GitLab Discord Google Bilibili QQ; do
        local var_name="${svc^^}_CLIENT_ID"
        local val="${!var_name:-}"
        if [[ -n "${val}" ]] && [[ "${val}" != "none" ]]; then
            echo "  ${svc}: 已配置"
            configured=$((configured + 1))
        fi
    done
    if [[ -n "${SMTP_HOST}" ]] && [[ "${SMTP_HOST}" != "none" ]]; then
        echo "  SMTP: 已配置 (${SMTP_HOST})"
        configured=$((configured + 1))
    fi
    [[ ${configured} -eq 0 ]] && echo "  (未配置任何第三方服务, 可部署后编辑 .env)"
}

# ---------------------- 环境检测 ----------------------
check_system() {
    step "检测系统环境"
    [[ $EUID -ne 0 ]] && error "请使用 root 用户运行此脚本"

    if ! grep -qi "ubuntu" /etc/os-release 2>/dev/null; then
        warn "本脚本针对 Ubuntu 优化，当前系统可能不兼容"
        grep -E "^(NAME|VERSION)=" /etc/os-release || true
        read -rp "是否继续? [y/N]: " CONFIRM
        [[ "${CONFIRM}" =~ ^[Yy]$ ]] || exit 1
    fi

    # 内存检测
    TOTAL_MEM=$(free -m | awk '/^Mem:/{print $2}')
    CPU_CORES=$(nproc)
    info "CPU 核心数: ${CPU_CORES}, 内存: ${TOTAL_MEM} MB"
    if [[ ${TOTAL_MEM} -lt 7000 ]]; then
        warn "当前内存 ${TOTAL_MEM}MB 低于推荐 8GB，将自动添加 Swap"
    fi
    if [[ ${CPU_CORES} -lt 4 ]]; then
        warn "CPU 核心数 ${CPU_CORES} 较少，Rust 编译可能较慢"
    fi
}

# ---------------------- Swap 设置 ----------------------
setup_swap() {
    step "配置 Swap 空间"
    local SWAP_SIZE="${SWAP_SIZE:-4G}"
    if [[ $(swapon --show | wc -l) -gt 0 ]]; then
        info "已存在 Swap，跳过"
        swapon --show
        return
    fi
    info "创建 ${SWAP_SIZE} Swap 文件"
    fallocate -l "${SWAP_SIZE}" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=4096
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
    sysctl vm.swappiness=10
    info "Swap 配置完成"
}

# ---------------------- 安装宝塔面板 ----------------------
install_baota() {
    step "安装宝塔面板"
    if [[ -f /etc/init.d/bt ]] || command -v bt &>/dev/null; then
        info "宝塔面板已安装"
        bt default 2>/dev/null || true
        return
    fi
    info "下载并安装宝塔面板 (Ubuntu 专用脚本)"
    curl -sSO https://download.bt.cn/install/install-ubuntu_6.0.sh
    yes | bash install-ubuntu_6.0.sh ed8484bec
    rm -f install-ubuntu_6.0.sh
    info "宝塔面板安装完成"
    bt default 2>/dev/null || warn "请手动运行 'bt default' 查看登录信息"
}

# ---------------------- 安装基础软件 ----------------------
install_dependencies() {
    step "安装系统依赖"
    apt-get update -y
    apt-get install -y --no-install-recommends \
        curl wget git build-essential pkg-config \
        ca-certificates gnupg lsb-release \
        xxd openssl ufw cron \
        nginx unzip htop vim \
        libssl-dev libpq-dev
    apt-get clean
    info "系统依赖安装完成"
}

# ---------------------- 安装 Docker ----------------------
install_docker() {
    step "安装 Docker"
    if command -v docker &>/dev/null; then
        info "Docker 已安装: $(docker --version)"
    else
        info "通过宝塔 Docker 管理器或官方脚本安装"
        curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
        systemctl enable docker
        systemctl start docker
    fi

    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        info "安装 docker-compose 插件"
        apt-get install -y docker-compose-plugin
    fi

    # 配置 Docker 镜像加速
    mkdir -p /etc/docker
    if ! grep -q "registry-mirrors" /etc/docker/daemon.json 2>/dev/null; then
        cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com",
    "https://docker.nju.edu.cn"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "100m", "max-file": "3" }
}
EOF
        systemctl daemon-reload
        systemctl restart docker
    fi
    info "Docker 就绪"
}

# ---------------------- 安装 Node.js / pnpm ----------------------
install_nodejs() {
    step "安装 Node.js 与 pnpm"
    if ! command -v node &>/dev/null || [[ "$(node -v | cut -dv -f2 | cut -d. -f1)" -lt 20 ]]; then
        info "安装 Node.js 20 LTS (通过 NodeSource)"
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y nodejs
    fi
    info "Node 版本: $(node -v)"

    if ! command -v pnpm &>/dev/null; then
        npm install -g pnpm@9.4.0
    fi
    info "pnpm 版本: $(pnpm -v)"

    # 配置 npm 镜像
    npm config set registry https://registry.npmmirror.com
}

# ---------------------- 安装 Rust ----------------------
install_rust() {
    step "安装 Rust 工具链"
    if ! command -v cargo &>/dev/null; then
        info "通过 rustup 安装 Rust (stable)"
        # 项目所需 edition = 2024, 要求 Rust >= 1.85; stable 即可满足
        # 默认使用官方源, 不可用时切换到国内镜像
        local sources=(
            "https://static.rust-lang.org|官方源"
            "https://mirrors.ustc.edu.cn/rustup|USTC"
            "https://mirrors.tuna.tsinghua.edu.cn/rustup|清华"
            "https://mirrors.rustcc.com/rustup|RustCC"
        )
        local installed=0
        for entry in "${sources[@]}"; do
            local mirror="${entry%%|*}"
            local name="${entry##*|}"
            info "尝试 [${name}]: ${mirror}"
            export RUSTUP_DIST_SERVER="${mirror}"
            export RUSTUP_UPDATE_ROOT="${mirror}/rustup"
            # 测试连通性 (5秒超时)
            if ! curl -fsSL --connect-timeout 5 --max-time 10 -o /dev/null "${mirror}/dist/channel-rust-stable.toml.sha256" 2>/dev/null; then
                warn "[${name}] 不可用, 切换下一个源"
                continue
            fi
            if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
               sh -s -- -y --default-toolchain stable --profile minimal; then
                installed=1
                info "使用 [${name}] 安装成功"
                break
            else
                warn "[${name}] 安装失败, 切换下一个源"
                rm -rf "${HOME}/.cargo" "${HOME}/.rustup" 2>/dev/null || true
            fi
        done
        [[ ${installed} -eq 1 ]] || error "所有 Rust 源均不可用, 请检查网络后重试"
        source "${HOME}/.cargo/env"
    else
        info "Rust 已安装: $(rustc --version)"
        source "${HOME}/.cargo/env" 2>/dev/null || true
    fi

    # 写入环境变量
    grep -q 'source "${HOME}/.cargo/env"' "${HOME}/.bashrc" || echo 'source "${HOME}/.cargo/env"' >> "${HOME}/.bashrc"

    # 配置 cargo crates.io 源 (默认官方, 不可用切换镜像)
    configure_cargo_registry

    source "${HOME}/.cargo/env"
    info "Rust 版本: $(rustc --version)"
    info "Cargo 版本: $(cargo --version)"
}

# ---------------------- 配置 cargo crates 源 ----------------------
# 默认使用官方 crates.io, 不可用时自动切换到国内镜像
# 每个源先用 curl 测试连通性, 通过才写入配置
configure_cargo_registry() {
    mkdir -p "${HOME}/.cargo"
    local config_file="${HOME}/.cargo/config.toml"

    # 候选源: 官方优先, 不可用切换 (sparse 协议更快, 无需 git clone 整个索引)
    # 格式: 名称|sparse-url|测试URL
    local registries=(
        "official|sparse+https://index.crates.io/|https://index.crates.io/config.json"
        "rsproxy|sparse+https://rsproxy.cn/index/|https://rsproxy.cn/index/config.json"
        "tuna|sparse+https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/|https://mirrors.tuna.tsinghua.edu.cn/crates.io-index/config.json"
        "bfsu|sparse+https://mirrors.bfsu.edu.cn/crates.io-index/|https://mirrors.bfsu.edu.cn/crates.io-index/config.json"
        "sjtug|sparse+https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/|https://mirrors.sjtug.sjtu.edu.cn/git/crates.io-index/config.json"
    )

    # 始终重新选择源 (避免旧配置残留导致编译失败)
    if [[ -f "${config_file}" ]]; then
        info "检测到已有 cargo 配置, 重新测试并选择最佳源"
        rm -rf "${HOME}/.cargo/registry/cache" "${HOME}/.cargo/registry/index" 2>/dev/null || true
    fi

    for entry in "${registries[@]}"; do
        local name="${entry%%|*}"
        local rest="${entry#*|}"
        local sparse_url="${rest%%|*}"
        local test_url="${rest##*|}"

        info "测试 crates 源 [${name}]: ${sparse_url}"
        # 测试连通性 (5s 连接, 10s 最大时长)
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 5 --max-time 10 "${test_url}" 2>/dev/null || echo "000")

        if [[ "${http_code}" == "200" ]] || [[ "${http_code}" == "404" ]]; then
            # 200 = 正常, 404 = 索引存在但该路径无文件 (也算可达)
            info "[${name}] 可用 (HTTP ${http_code}), 写入 cargo 配置"

            if [[ "${name}" == "official" ]]; then
                # 官方源 = crates-io 默认, 不能用 replace-with (会重复定义)
                # 直接使用默认, 仅写入 [net] 配置
                cat > "${config_file}" <<EOF
# 自动生成 - cargo crates.io 源配置
# 当前使用: 官方源 (index.crates.io, 不替换默认)
# 如需切换, 删除此文件后重新运行脚本

[net]
git-fetch-with-cli = true
retry = 5
EOF
            else
                # 镜像源: 用 replace-with 替换 crates-io
                cat > "${config_file}" <<EOF
# 自动生成 - cargo crates.io 源配置
# 当前使用: ${name} (${sparse_url})
# 如需切换, 删除此文件后重新运行脚本

[source.crates-io]
replace-with = "${name}"

[source.${name}]
registry = "${sparse_url}"

[net]
git-fetch-with-cli = true
retry = 5
EOF
            fi
            info "cargo 配置已写入: ${config_file}"
            return 0
        else
            warn "[${name}] 不可用 (HTTP ${http_code}), 切换下一个源"
        fi
    done

    # 所有镜像都不可用, 使用官方默认 (不替换)
    warn "所有 crates 镜像均不可用, 使用 cargo 官方默认源 (可能较慢)"
    cat > "${config_file}" <<'EOF'
# 自动生成 - 使用官方 crates.io (无镜像)
[net]
git-fetch-with-cli = true
retry = 5
EOF
}

# ---------------------- 拉取代码 ----------------------
clone_repo() {
    step "拉取项目代码"
    mkdir -p "$(dirname "${INSTALL_DIR}")"
    if [[ -d "${INSTALL_DIR}/.git" ]]; then
        info "代码目录已存在，执行更新"
        cd "${INSTALL_DIR}"
        git fetch --all
        git checkout "${REPO_BRANCH}"
        git reset --hard "origin/${REPO_BRANCH}"
    else
        info "克隆仓库: ${REPO_URL}"
        git clone -b "${REPO_BRANCH}" "${REPO_URL}" "${INSTALL_DIR}"
        cd "${INSTALL_DIR}"
    fi
    info "当前 commit: $(git rev-parse --short HEAD)"
}

# ---------------------- 启动数据库服务 ----------------------
start_databases() {
    step "启动数据库服务 (Docker Compose)"
    mkdir -p "${DATA_DIR}"/{postgres,redis,meilisearch,clickhouse,uploads}

    cd "${INSTALL_DIR}"
    # 生成生产环境 docker-compose
    cat > docker-compose.prod.yml <<EOF
services:
  postgres_db:
    image: postgres:16-alpine
    container_name: bbsmc-postgres
    restart: always
    ports:
      - '127.0.0.1:${PG_PORT}:5432'
    volumes:
      - '${DATA_DIR}/postgres:/var/lib/postgresql/data'
    environment:
      POSTGRES_USER: labrinth
      POSTGRES_PASSWORD: ${PG_PASS}
      POSTGRES_DB: labrinth
      POSTGRES_HOST_AUTH_METHOD: scram-sha-256
    healthcheck:
      test: ['CMD', 'pg_isready', '-U', 'labrinth']
      interval: 5s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    container_name: bbsmc-redis
    restart: always
    ports:
      - '127.0.0.1:${REDIS_PORT}:6379'
    volumes:
      - '${DATA_DIR}/redis:/data'
    command: redis-server --requirepass ${REDIS_PASS} --appendonly yes
    healthcheck:
      test: ['CMD', 'redis-cli', '-a', '${REDIS_PASS}', 'PING']
      interval: 5s
      timeout: 5s
      retries: 5

  meilisearch:
    image: getmeili/meilisearch:v1.12.0
    container_name: bbsmc-meilisearch
    restart: always
    ports:
      - '127.0.0.1:${MEILI_PORT}:7700'
    volumes:
      - '${DATA_DIR}/meilisearch:/data.ms'
    environment:
      MEILI_MASTER_KEY: ${MEILI_KEY}
      MEILI_HTTP_PAYLOAD_SIZE_LIMIT: 107374182400
      MEILI_LOG_LEVEL: warn
    healthcheck:
      test: ['CMD', 'curl', '--fail', 'http://localhost:7700/health']
      interval: 5s
      timeout: 5s
      retries: 5

  clickhouse:
    image: clickhouse/clickhouse-server:24.3
    container_name: bbsmc-clickhouse
    restart: always
    ports:
      - '127.0.0.1:${CH_PORT}:8123'
    volumes:
      - '${DATA_DIR}/clickhouse:/var/lib/clickhouse'
    environment:
      CLICKHOUSE_USER: default
      CLICKHOUSE_PASSWORD: ${CH_PASS}
      CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT: 1
    ulimits:
      nofile:
        soft: 262144
        hard: 262144
    healthcheck:
      test: ['CMD', 'clickhouse-client', '--query', 'SELECT 1']
      interval: 5s
      timeout: 5s
      retries: 5
EOF

    docker compose -f docker-compose.prod.yml up -d
    info "等待数据库就绪..."
    sleep 15
    docker compose -f docker-compose.prod.yml ps

    # ---------- 验证并修复 PostgreSQL 密码 ----------
    # 如果容器已存在, 密码可能与新生成的不一致
    info "验证 PostgreSQL 连接..."
    local pg_test
    pg_test=$(docker exec bbsmc-postgres pg_isready -U labrinth -d labrinth 2>/dev/null || echo "failed")
    if ! echo "${pg_test}" | grep -q "accepting connections"; then
        local pg_auth_test
        pg_auth_test=$(docker exec bbsmc-postgres \
            PGPASSWORD="${PG_PASS}" psql -U labrinth -d labrinth -c "SELECT 1" 2>&1 || echo "failed")
        if echo "${pg_auth_test}" | grep -q "password authentication failed\|authentication failed"; then
            warn "PostgreSQL 密码认证失败! 尝试用 ALTER USER 修复..."
            # 尝试用 postgres 用户修改密码 (容器默认 postgres 无密码, 信任认证)
            local alter_result
            alter_result=$(docker exec bbsmc-postgres \
                psql -U postgres -c "ALTER USER labrinth PASSWORD '${PG_PASS}';" 2>&1 || echo "failed")
            if echo "${alter_result}" | grep -q "ALTER ROLE"; then
                info "PostgreSQL 密码已修复"
                # 验证修复后的连接
                pg_auth_test=$(docker exec bbsmc-postgres \
                    PGPASSWORD="${PG_PASS}" psql -U labrinth -d labrinth -c "SELECT 1" 2>&1 || echo "failed")
                if echo "${pg_auth_test}" | grep -q "1 row"; then
                    info "PostgreSQL 密码验证通过"
                else
                    error "PostgreSQL 密码修复后仍无法连接!"
                    error "可能是数据卷残留导致, 请手动重置:"
                    error "  docker compose -f docker-compose.prod.yml down -v"
                    error "  rm -rf ${DATA_DIR}/postgres"
                    error "  然后重新运行 ./deploy.sh"
                    exit 1
                fi
            elif echo "${alter_result}" | grep -q "role.*does not exist\|does not exist"; then
                # labrinth 用户不存在 (数据卷被清空但容器还在), 需要重建
                warn "labrinth 角色不存在 (数据卷可能已被清空), 自动重置容器..."
                cd "${INSTALL_DIR}"
                docker compose -f docker-compose.prod.yml down 2>/dev/null || true
                rm -rf "${DATA_DIR}/postgres"
                docker compose -f docker-compose.prod.yml up -d postgres_db
                info "等待 PostgreSQL 重新初始化..."
                sleep 15
                # 再次验证
                pg_auth_test=$(docker exec bbsmc-postgres \
                    PGPASSWORD="${PG_PASS}" psql -U labrinth -d labrinth -c "SELECT 1" 2>&1 || echo "failed")
                if echo "${pg_auth_test}" | grep -q "1 row"; then
                    info "PostgreSQL 重建成功, 密码验证通过"
                else
                    error "PostgreSQL 重建后仍无法连接!"
                    exit 1
                fi
            else
                error "PostgreSQL 密码修复失败!"
                error "ALTER USER 输出: ${alter_result}"
                exit 1
            fi
        elif echo "${pg_auth_test}" | grep -q "1 row"; then
            info "PostgreSQL 密码验证通过"
        else
            warn "无法验证 PostgreSQL 密码, 继续部署 (首次部署通常正常)"
        fi
    else
        info "PostgreSQL 连接正常"
    fi

    info "数据库服务启动完成"
}

# ---------------------- 重启 Docker 服务 ----------------------
restart_docker_services() {
    step "重启所有 Docker 服务"

    local INSTALL_DIR="${INSTALL_DIR:-/www/wwwroot/bbsmc}"
    local DATA_DIR="${DATA_DIR:-/www/wwwroot/bbsmc-data}"
    local COMPOSE_FILE="${INSTALL_DIR}/docker-compose.prod.yml"

    cd "${INSTALL_DIR}"

    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        warn "未找到 docker-compose.prod.yml, 尝试使用默认 docker-compose.yml..."
        COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
    fi

    if [[ ! -f "${COMPOSE_FILE}" ]]; then
        error "未找到 docker-compose 配置文件"
        return 1
    fi

    if ! command -v docker &>/dev/null; then
        error "Docker 未安装"
        return 1
    fi

    info "使用配置文件: ${COMPOSE_FILE}"
    echo ""

    echo -e "${YELLOW}当前服务状态:${NC}"
    docker compose -f "${COMPOSE_FILE}" ps 2>/dev/null || docker-compose -f "${COMPOSE_FILE}" ps

    echo ""
    echo -e "${YELLOW}正在停止所有服务...${NC}"
    docker compose -f "${COMPOSE_FILE}" down 2>/dev/null || docker-compose -f "${COMPOSE_FILE}" down
    sleep 3

    echo ""
    echo -e "${YELLOW}正在启动所有服务...${NC}"
    docker compose -f "${COMPOSE_FILE}" up -d 2>/dev/null || docker-compose -f "${COMPOSE_FILE}" up -d
    sleep 5

    echo ""
    echo -e "${YELLOW}等待服务就绪 (15秒)...${NC}"
    sleep 15

    echo ""
    echo -e "${YELLOW}服务状态:${NC}"
    docker compose -f "${COMPOSE_FILE}" ps 2>/dev/null || docker-compose -f "${COMPOSE_FILE}" ps

    echo ""
    echo -e "${YELLOW}健康检查:${NC}"

    local all_healthy=true
    local services=("bbsmc-postgres:5432" "bbsmc-redis:6379" "bbsmc-meilisearch:7700" "bbsmc-clickhouse:8123")

    for svc in "${services[@]}"; do
        local container="${svc%%:*}"
        local port="${svc##*:}"

        local status
        status=$(docker inspect -f '{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "not_found")

        if [[ "${status}" == "healthy" ]]; then
            echo -e "  ${GREEN}✓${NC} ${container} (port ${port}) - healthy"
        elif [[ "${status}" == "unhealthy" ]]; then
            echo -e "  ${RED}✗${NC} ${container} (port ${port}) - unhealthy"
            all_healthy=false
        elif [[ "${status}" == "not_found" ]]; then
            local alt_container
            alt_container=$(docker ps --filter "publish=${port}" --format '{{.Names}}' 2>/dev/null | head -1)
            if [[ -n "${alt_container}" ]]; then
                local alt_status
                alt_status=$(docker inspect -f '{{.State.Health.Status}}' "${alt_container}" 2>/dev/null || echo "unknown")
                echo -e "  ${GREEN}✓${NC} ${alt_container} (port ${port}) - ${alt_status}"
            else
                echo -e "  ${RED}✗${NC} ${container} (port ${port}) - container not found"
                all_healthy=false
            fi
        else
            echo -e "  ${YELLOW}?${NC} ${container} (port ${port}) - ${status}"
        fi
    done

    echo ""
    if [[ "${all_healthy}" == "true" ]]; then
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}  ✓ 所有 Docker 服务已重启并运行正常!${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
    else
        echo -e "${YELLOW}部分服务可能未完全就绪, 请检查日志:${NC}"
        echo -e "  docker logs --tail 50 bbsmc-postgres"
        echo -e "  docker logs --tail 50 bbsmc-redis"
        echo -e "  docker logs --tail 50 bbsmc-meilisearch"
        echo -e "  docker logs --tail 50 bbsmc-clickhouse"
    fi
}

# ---------------------- 生成环境配置 ----------------------
gen_env_files() {
    step "生成环境配置文件"

    cd "${INSTALL_DIR}"

    # 清理旧 .env 中可能存在的危险变量 (REDIS_WAIT_TIMEOUT_MS 会导致 parse panic)
    local env_files=("apps/labrinth/.env" "apps/frontend/.env")
    for ef in "${env_files[@]}"; do
        if [[ -f "${ef}" ]]; then
            sed -i '/^REDIS_WAIT_TIMEOUT_MS=/d' "${ef}" 2>/dev/null || true
        fi
    done

    # ---------- Labrinth .env ----------
    cat > apps/labrinth/.env <<EOF
DEBUG=false
RUST_LOG=info,sqlx::query=warn,actix_web=info
SENTRY_DSN=none

# 站点基础 URL (可选, fail-open)
#   - 仅用于风控告警通知卡片中的跳转链接
#   - 缺失/为空时, 风控检测照常执行, 仅告警卡片缺少 URL
SITE_URL=https://${DOMAIN}
CDN_URL=https://${CDN_DOMAIN}/bbsmc
CDN_PRIVATE_URL=none
SELF_ADDR=https://${API_DOMAIN}
LABRINTH_ADMIN_KEY=${ADMIN_KEY}
RATE_LIMIT_IGNORE_KEY=${ADMIN_KEY}

DATABASE_URL=postgresql://labrinth:${PG_PASS}@127.0.0.1:${PG_PORT}/labrinth
DATABASE_MIN_CONNECTIONS=2
DATABASE_MAX_CONNECTIONS=32

MEILISEARCH_ADDR=http://127.0.0.1:${MEILI_PORT}
MEILISEARCH_KEY=${MEILI_KEY}

REDIS_URL=redis://:${REDIS_PASS}@127.0.0.1:${REDIS_PORT}
REDIS_MAX_CONNECTIONS=10000
REDIS_NAMESPACE=none

BIND_ADDR=127.0.0.1:${BACKEND_PORT}

MODERATION_SLACK_WEBHOOK=
PUBLIC_DISCORD_WEBHOOK=
CLOUDFLARE_INTEGRATION=false

STORAGE_BACKEND=local
MOCK_FILE_PATH=${DATA_DIR}/uploads

BACKBLAZE_KEY_ID=none
BACKBLAZE_KEY=none
BACKBLAZE_BUCKET_ID=none

S3_ACCESS_TOKEN=none
S3_SECRET=none
S3_URL=none
S3_REGION=none
S3_BUCKET_NAME=none
S3_PRIVATE_BUCKET_NAME=none

LOCAL_INDEX_INTERVAL=3600
VERSION_INDEX_INTERVAL=1800

RATE_LIMIT_IGNORE_IPS='["127.0.0.1"]'

WHITELISTED_MODPACK_DOMAINS='["${CDN_DOMAIN}", "github.com", "raw.githubusercontent.com"]'

ALLOWED_CALLBACK_URLS='["localhost", ".${DOMAIN}", "127.0.0.1"]'

# ============================================
# OAuth 第三方登录配置
# 回调地址: https://${API_DOMAIN}/auth/callback/{provider}
# ============================================
GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID}
GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET}
GITLAB_CLIENT_ID=${GITLAB_CLIENT_ID}
GITLAB_CLIENT_SECRET=${GITLAB_CLIENT_SECRET}
DISCORD_CLIENT_ID=${DISCORD_CLIENT_ID}
DISCORD_CLIENT_SECRET=${DISCORD_CLIENT_SECRET}
MICROSOFT_CLIENT_ID=${MICROSOFT_CLIENT_ID}
MICROSOFT_CLIENT_SECRET=${MICROSOFT_CLIENT_SECRET}
GOOGLE_CLIENT_ID=${GOOGLE_CLIENT_ID}
GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
BILIBILI_CLIENT_ID=${BILIBILI_CLIENT_ID}
BILIBILI_CLIENT_SECRET=${BILIBILI_CLIENT_SECRET}
QQ_CLIENT_ID=${QQ_CLIENT_ID}
QQ_CLIENT_SECRET=${QQ_CLIENT_SECRET}

# ============================================
# 注意: Gitee 登录需要修改 Rust 源码添加 Provider
# 原生 AuthProvider 枚举不包含 Gitee, 仅修改 .env 无效
# ============================================

# ============================================
# 支付配置
# ============================================
PAYPAL_API_URL=https://api-m.sandbox.paypal.com/v1/
PAYPAL_WEBHOOK_ID=none
PAYPAL_CLIENT_ID=${PAYPAL_CLIENT_ID}
PAYPAL_CLIENT_SECRET=${PAYPAL_CLIENT_SECRET}

STRIPE_API_KEY=${STRIPE_API_KEY}
STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET}

STEAM_API_KEY=none

TREMENDOUS_API_URL=https://testflight.tremendous.com/api/v2/
TREMENDOUS_API_KEY=none
TREMENDOUS_PRIVATE_KEY=none
TREMENDOUS_CAMPAIGN_ID=none

# ============================================
# SMTP 邮件配置
# ============================================
HCAPTCHA_SECRET=none
TAC_URL=none
SMTP_USERNAME=${SMTP_USERNAME}
SMTP_PASSWORD=${SMTP_PASSWORD}
SMTP_HOST=${SMTP_HOST}

SITE_VERIFY_EMAIL_PATH=none
SITE_RESET_PASSWORD_PATH=none
SITE_BILLING_PATH=none

BEEHIIV_PUBLICATION_ID=none
BEEHIIV_API_KEY=none

ANALYTICS_ALLOWED_ORIGINS='["https://${DOMAIN}", "https://www.${DOMAIN}", "https://${API_DOMAIN}", "*"]'

CLICKHOUSE_URL=http://127.0.0.1:${CH_PORT}
CLICKHOUSE_USER=default
CLICKHOUSE_PASSWORD=${CH_PASS}
CLICKHOUSE_DATABASE=staging_ariadne

MAXMIND_LICENSE_KEY=none
FLAME_ANVIL_URL=none

STRIPE_API_KEY=none
STRIPE_WEBHOOK_SECRET=none

ADITUDE_API_KEY=none
PYRO_API_KEY=none

DEV=false

# 飞书机器人 Webhook (可选, best-effort)
#   - 用于文本/图片风控告警通知
#   - 设为 none / 留空 / 缺失: 跳过发送, 不影响任何业务流程 (fail-open)
#   - 配置格式: https://open.feishu.cn/open-apis/bot/v2/hook/xxxxxxxx
FEISHU_BOT_WEBHOOK=none

ALIYUN_SMS_ACCESS_KEYID=none
ALIYUN_SMS_ACCESS_KEY_SECRET=none
ALIYUN_SMS_REGION=none
ALIYUN_SMS_REPORT_TEMPLETE_CODE=none
ALIYUN_SMS_SIGN_NAME=none

# 火山引擎风控 AK/SK (可选, fail-open)
#   - 用于用户名、项目描述、图片等内容安全检测
#   - 设为 none / 留空 / 缺失: 跳过风控检测, 直接放行, 不影响注册/发布等核心流程
#   - 控制台地址: https://console.volcengine.com/iam/keymanage
HUOSHAN_AK=none
HUOSHAN_SK=none

ENCRYPTION_KEY=${ENCRYPTION_KEY}

SEVENPAY_API_URL=none
SEVENPAY_CREATE_ORDER_PATH=none
SEVENPAY_QUERY_ORDER_PATH=none
SEVENPAY_VERIFY_MERCHANT_PATH=none
SEVENPAY_KEYCODE=none
SEVENPAY_ALLOWED_IPS=none
EOF

    # 确保 REDIS_WAIT_TIMEOUT_MS 未被意外写入 (默认 u64 解析会 panic)
    sed -i '/^REDIS_WAIT_TIMEOUT_MS=/d' apps/labrinth/.env 2>/dev/null || true

    # ---------- Frontend .env ----------
    cat > apps/frontend/.env <<EOF
BASE_URL=https://${API_DOMAIN}/v2/
BROWSER_BASE_URL=https://${API_DOMAIN}/v2/
EOF

    # 校验前端 API URL 格式 (防止域名拼接错误)
    local fe_api_check
    fe_api_check=$(grep "^BROWSER_BASE_URL=" apps/frontend/.env 2>/dev/null | cut -d= -f2)
    local fe_check_host
    fe_check_host=$(echo "${fe_api_check}" | sed 's|https\?://||' | cut -d/ -f1)
    local fe_check_parts
    fe_check_parts=$(echo "${fe_check_host}" | tr '.' '\n' | wc -l)
    if [[ ${fe_check_parts} -gt 3 ]]; then
        warn "前端 .env API 域名可能异常: ${fe_check_host} (域名层级过多, 检查是否重复拼接)"
        warn "BROWSER_BASE_URL=${fe_api_check}"
    fi

    # ---------- 保存凭据到文件 ----------
    cat > "${INSTALL_DIR}/deploy-credentials.txt" <<EOF
# ============================================
# BBSMC 部署凭据 (请妥善保管, 切勿提交到仓库)
# ============================================
主域名:        ${DOMAIN}
API 域名:      ${API_DOMAIN}
CDN 域名:      ${CDN_DOMAIN}

PostgreSQL:    labrinth:${PG_PASS}@127.0.0.1:${PG_PORT}/labrinth
Redis:         127.0.0.1:${REDIS_PORT} (密码: ${REDIS_PASS})
Meilisearch:   http://127.0.0.1:${MEILI_PORT} (Key: ${MEILI_KEY})
ClickHouse:    http://127.0.0.1:${CH_PORT} (default/${CH_PASS})

Labrinth Admin Key:    ${ADMIN_KEY}
Encryption Key:        ${ENCRYPTION_KEY}

安装目录:      ${INSTALL_DIR}
数据目录:      ${DATA_DIR}
EOF
    chmod 600 "${INSTALL_DIR}/deploy-credentials.txt"
    info "凭据已保存到: ${INSTALL_DIR}/deploy-credentials.txt"

    # 将 .env 复制到 bin/ 目录 (labrinth 运行时 dotenvy 从工作目录加载)
    # 如果 bin 目录尚未创建, 将在 build_backend 完成后再次复制
    if [[ -d "${INSTALL_DIR}/bin" ]]; then
        cp -f apps/labrinth/.env "${INSTALL_DIR}/bin/.env"
        info "已将 .env 同步到 bin/.env (dotenvy 从工作目录加载)"
    fi
}

# ---------------------- 修复项目级 cargo 配置 ----------------------
# 项目自带 .cargo/config.toml 硬编码了失效的 USTC 镜像, 优先级高于用户级配置
# 此函数备份并移除项目级镜像配置, 让 cargo 回退到用户级 ~/.cargo/config.toml
fix_project_cargo_config() {
    step "修复项目级 cargo 配置"
    cd "${INSTALL_DIR}"

    local configs=(
        "${INSTALL_DIR}/.cargo/config.toml"
        "${INSTALL_DIR}/apps/labrinth/.cargo/config.toml"
    )

    for cfg in "${configs[@]}"; do
        if [[ ! -f "${cfg}" ]]; then
            continue
        fi
        # 备份原始配置 (仅首次)
        if [[ ! -f "${cfg}.orig" ]]; then
            cp "${cfg}" "${cfg}.orig"
            info "已备份: ${cfg} -> ${cfg}.orig"
        fi

        # 检查是否包含失效的 USTC 镜像配置
        if grep -q "mirrors.ustc.edu.cn/crates.io-index" "${cfg}"; then
            info "修复失效的 USTC 镜像配置: ${cfg}"
            # 移除 source 替换, 保留其他配置 (如 target.rustflags)
            # 用 sed 删除 [source.crates-io], [source.ustc], [source.tuna] 及其内容
            sed -i '/\[source\.crates-io\]/,/^$/d' "${cfg}"
            sed -i '/\[source\.ustc\]/,/^$/d' "${cfg}"
            sed -i '/\[source\.tuna\]/,/^$/d' "${cfg}"
            sed -i '/^replace-with/d' "${cfg}"
            info "已移除项目级镜像配置, cargo 将使用用户级 ~/.cargo/config.toml"
        else
            info "配置正常, 跳过: ${cfg}"
        fi
    done
}

# ---------------------- 构建 Labrinth ----------------------
build_backend() {
    step "构建 Labrinth (Rust 后端)"
    cd "${INSTALL_DIR}"

    # 修复项目级 cargo 配置 (必须在 cargo build 之前)
    fix_project_cargo_config

    info "准备 SQLx 离线模式 (避免编译时连接数据库)"
    # 确保有 sqlx-data
    if [[ ! -f apps/labrinth/sqlx-data.json ]]; then
        warn "未找到 sqlx-data.json, 启用本地数据库进行 prepare"
        export DATABASE_URL="postgresql://labrinth:${PG_PASS}@127.0.0.1:${PG_PORT}/labrinth"
    fi
    export SQLX_OFFLINE=true

    info "开始 cargo build --release (耗时较长, 请耐心等待)"
    source "${HOME}/.cargo/env"

    # 显示当前生效的 cargo 配置
    info "当前 cargo 配置来源:"
    cargo config get source.crates-io 2>/dev/null || true

    cargo build --release --package labrinth

    # 复制产物
    mkdir -p "${INSTALL_DIR}/bin"
    cp -f "${INSTALL_DIR}/target/release/labrinth" "${INSTALL_DIR}/bin/labrinth"
    cp -rf "${INSTALL_DIR}/apps/labrinth/migrations" "${INSTALL_DIR}/bin/"
    cp -rf "${INSTALL_DIR}/apps/labrinth/assets" "${INSTALL_DIR}/bin/"

    # 将 .env 复制到 bin/ 目录 (labrinth 使用 dotenvy 从工作目录加载)
    cp -f "${INSTALL_DIR}/apps/labrinth/.env" "${INSTALL_DIR}/bin/.env"
    info "已将 .env 同步到 bin/.env (dotenvy 从工作目录加载)"

    info "后端构建完成: ${INSTALL_DIR}/bin/labrinth"
}

# ---------------------- 运行数据库迁移 ----------------------
run_migrations() {
    step "运行数据库迁移"
    cd "${INSTALL_DIR}/bin"
    export DATABASE_URL="postgresql://labrinth:${PG_PASS}@127.0.0.1:${PG_PORT}/labrinth"

    # 确保 .env 在当前目录 (dotenvy 从工作目录加载)
    if [[ ! -f ".env" ]]; then
        warn "bin/.env 不存在, 从 apps/labrinth/.env 复制"
        cp -f "${INSTALL_DIR}/apps/labrinth/.env" ".env"
    fi

    # labrinth 启动时自动执行迁移, 迁移后会启动 HTTP 服务
    # 在后台启动, 等待迁移完成 (API 就绪), 然后关闭
    info "启动 labrinth 执行迁移..."
    ./labrinth > /var/log/bbsmc-migration.log 2>&1 &
    local MIG_PID=$!

    local max_wait=30
    local waited=0
    local migrated=0
    while [[ ${waited} -lt ${max_wait} ]]; do
        if grep -qi "migration\|running.*migrations\|migrations.*complete" /var/log/bbsmc-migration.log 2>/dev/null; then
            info "迁移已完成"
            migrated=1
            break
        fi
        if grep -qi "listening\|ready\|started\|server.*running" /var/log/bbsmc-migration.log 2>/dev/null; then
            info "迁移已完成, 服务已启动"
            migrated=1
            break
        fi
        # 检查进程是否还活着
        if ! kill -0 ${MIG_PID} 2>/dev/null; then
            warn "labrinth 进程已退出, 迁移可能失败"
            tail -20 /var/log/bbsmc-migration.log 2>/dev/null || true
            break
        fi
        sleep 2
        waited=$((waited + 2))
    done

    if [[ ${migrated} -eq 0 ]]; then
        warn "未检测到迁移完成日志, 检查 /var/log/bbsmc-migration.log"
        tail -30 /var/log/bbsmc-migration.log 2>/dev/null || true
    fi

    # 等待 API 就绪
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${BACKEND_PORT}/v2/tag/category" 2>/dev/null || echo "000")
    if [[ "${code}" == "200" ]] || [[ "${code}" == "401" ]] || [[ "${code}" == "403" ]]; then
        info "API 已就绪 (HTTP ${code})"
    else
        warn "API 未就绪 (HTTP ${code}), 日志:"
        tail -10 /var/log/bbsmc-migration.log 2>/dev/null || true
    fi

    # 关闭临时进程 (后续由 systemd 管理)
    kill ${MIG_PID} 2>/dev/null || true
    sleep 1
    # 确保进程已退出 (不使用 wait, 因为 labrinth 会一直运行)
    kill -9 ${MIG_PID} 2>/dev/null || true
    sleep 1
    info "数据库迁移完成"
}

# ---------------------- 构建前端 ----------------------
build_frontend() {
    step "构建前端 (Nuxt 3)"
    cd "${INSTALL_DIR}"

    # 校验前端 .env 中的 API URL
    local fe_api_url
    fe_api_url=$(grep "^BROWSER_BASE_URL=" apps/frontend/.env 2>/dev/null | cut -d= -f2)
    if [[ -n "${fe_api_url}" ]]; then
        local fe_host
        fe_host=$(echo "${fe_api_url}" | sed 's|https\?://||' | cut -d/ -f1)
        local domain_parts
        domain_parts=$(echo "${fe_host}" | tr '.' '\n' | wc -l)
        if [[ ${domain_parts} -gt 3 ]]; then
            warn "前端 .env 中 API 域名可能异常: ${fe_host} (域名层级过多)"
            warn "请检查 apps/frontend/.env 中的 BROWSER_BASE_URL"
        else
            info "前端 .env API URL: ${fe_api_url}"
        fi
    fi

    # 使用 --ignore-scripts 跳过 postinstall 中的 nuxi prepare
    # 因为 prepare 需要 API 就绪, 但此时可能后端还未完全启动
    info "安装依赖 (pnpm, 跳过 postinstall)"
    pnpm install --frozen-lockfile --ignore-scripts || pnpm install --ignore-scripts

    # 确保 src/generated/state.json 存在 (即使 API 未就绪也能构建)
    # 这是构建失败的常见原因: Vite 找不到 import 的 state.json
    info "预生成 state.json (确保构建就绪)"
    mkdir -p apps/frontend/src/generated
    local api_url_for_state="${fe_api_url:-https://${API_DOMAIN}/v2/}"
    local ts_now
    ts_now=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +%s)
    cat > apps/frontend/src/generated/state.json <<STATEEOF
{
  "lastGenerated": "${ts_now}",
  "apiUrl": "${api_url_for_state}",
  "categories": [],
  "loaders": [],
  "gameVersions": [],
  "donationPlatforms": [],
  "reportTypes": [],
  "homePageSearch": [],
  "homePageNotifs": []
}
STATEEOF

    # 默认使用 SKIP_BUILD_PREPARE=1 跳过 build:before 中的 API 预取
    # 如果后端已就绪, 可以尝试 API 预取 (带 TTL 缓存, 不会重复请求)
    info "构建前端 (默认跳过 API 预取, 使用缓存数据)..."
    if ! SKIP_BUILD_PREPARE=1 pnpm run web:build 2>&1; then
        error "前端构建失败, 请检查日志"
    fi

    # 复制产物
    mkdir -p "${INSTALL_DIR}/bin/frontend"
    cp -rf "${INSTALL_DIR}/apps/frontend/.output" "${INSTALL_DIR}/bin/frontend/"

    # 将 .env 复制到前端工作目录 (Nuxt 运行时从工作目录加载)
    cp -f "${INSTALL_DIR}/apps/frontend/.env" "${INSTALL_DIR}/bin/frontend/.output/.env"
    info "已将 .env 同步到前端工作目录"

    # 清理预生成的 state.json (避免污染源码, build:before 会在下次构建时重新生成)
    rm -f apps/frontend/src/generated/state.json

    info "前端构建完成: ${INSTALL_DIR}/bin/frontend/.output"
}

# ---------------------- Systemd 服务 ----------------------
setup_systemd_labrinth() {
    step "配置 Labrinth Systemd 服务"

    # 确保 .env 在 bin/ 目录 (labrinth 使用 dotenvy 从 WorkingDirectory 加载)
    if [[ ! -f "${INSTALL_DIR}/bin/.env" ]]; then
        warn "bin/.env 不存在, 从 apps/labrinth/.env 复制"
        cp -f "${INSTALL_DIR}/apps/labrinth/.env" "${INSTALL_DIR}/bin/.env"
    fi

    # 清理 bin/.env 中的 REDIS_WAIT_TIMEOUT_MS (防止 parse panic)
    sed -i '/^REDIS_WAIT_TIMEOUT_MS=/d' "${INSTALL_DIR}/bin/.env" 2>/dev/null || true

    # 验证 .env 关键字段
    info "验证 bin/.env 配置..."
    # 必需字段 (缺失会影响核心功能)
    local required_env_checks=("DATABASE_URL" "STORAGE_BACKEND" "BIND_ADDR" "LABRINTH_ADMIN_KEY")
    for var in "${required_env_checks[@]}"; do
        local val
        val=$(grep "^${var}=" "${INSTALL_DIR}/bin/.env" 2>/dev/null | cut -d= -f2)
        if [[ -z "${val}" ]]; then
            warn ".env 中缺少 ${var} (核心功能必需)"
        fi
    done
    # 可选字段 (缺失采用 fail-open, 不阻塞核心功能)
    local optional_env_checks=("SITE_URL" "HUOSHAN_AK" "HUOSHAN_SK" "FEISHU_BOT_WEBHOOK")
    for var in "${optional_env_checks[@]}"; do
        local val
        val=$(grep "^${var}=" "${INSTALL_DIR}/bin/.env" 2>/dev/null | cut -d= -f2)
        if [[ -z "${val}" ]] || [[ "${val}" == "none" ]]; then
            case "${var}" in
                SITE_URL)
                    info "  .env 中 SITE_URL 未配置: 风控告警卡片中的链接将为空 (不影响业务)"
                    ;;
                HUOSHAN_AK|HUOSHAN_SK)
                    info "  .env 中 ${var} 未配置: 跳过火山引擎内容风控检测, 注册/发布直接放行 (fail-open)"
                    ;;
                FEISHU_BOT_WEBHOOK)
                    info "  .env 中 FEISHU_BOT_WEBHOOK 未配置: 不发送风控飞书告警通知 (best-effort)"
                    ;;
            esac
        fi
    done

    # 注意: 不使用 EnvironmentFile, 因为 dotenv 文件格式 (引号/数组/注释) 与 systemd 不兼容
    # labrinth 使用 dotenvy 从 WorkingDirectory 加载 .env 文件
    cat > /etc/systemd/system/bbsmc-labrinth.service <<EOF
[Unit]
Description=BBSMC Labrinth API Server
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/bin
ExecStart=${INSTALL_DIR}/bin/labrinth
Restart=always
RestartSec=5
StandardOutput=append:/var/log/bbsmc-labrinth.log
StandardError=append:/var/log/bbsmc-labrinth.log
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable bbsmc-labrinth
    systemctl restart bbsmc-labrinth

    # 等待并验证服务是否真正启动
    sleep 3
    local active_state
    active_state=$(systemctl is-active bbsmc-labrinth 2>/dev/null)
    if [[ "${active_state}" != "active" ]]; then
        warn "Labrinth 服务未处于 active 状态: ${active_state}"
        warn "最近日志:"
        journalctl -u bbsmc-labrinth -n 20 --no-pager 2>/dev/null || true
        warn "尝试查看完整日志:"
        tail -20 /var/log/bbsmc-labrinth.log 2>/dev/null || true
    else
        info "Labrinth 服务已启动 (状态: active)"
    fi
}

# 等待后端 API 就绪 (给前端 build:before 使用)
wait_for_backend() {
    step "等待后端 API 就绪"
    local max_wait=90
    local waited=0
    local backend_url="http://127.0.0.1:${BACKEND_PORT}/v2/tag/category"

    while [[ ${waited} -lt ${max_wait} ]]; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 3 --max-time 5 "${backend_url}" 2>/dev/null || echo "000")
        if [[ "${code}" == "200" ]] || [[ "${code}" == "401" ]] || [[ "${code}" == "403" ]]; then
            info "后端 API 已就绪 (HTTP ${code})"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
        printf "\r  等待后端就绪... %ds (HTTP %s)   " "${waited}" "${code}"
    done
    echo ""
    warn "后端 API 未在 ${max_wait}s 内就绪, 继续构建 (build:before 将使用缓存)"
    warn "可通过 journalctl -u bbsmc-labrinth 查看服务状态"
    return 0
}

setup_systemd_frontend() {
    step "配置 Frontend Systemd 服务"

    # 确保 .output 目录存在 (避免 CHDIR 错误)
    local FE_OUTPUT="${INSTALL_DIR}/bin/frontend/.output"
    if [[ ! -f "${FE_OUTPUT}/server/index.mjs" ]]; then
        warn "${FE_OUTPUT}/server/index.mjs 不存在!"
        if [[ -d "${INSTALL_DIR}/apps/frontend/.output" ]]; then
            warn "从 apps/frontend/.output 重新复制..."
            mkdir -p "${INSTALL_DIR}/bin/frontend"
            cp -rf "${INSTALL_DIR}/apps/frontend/.output" "${INSTALL_DIR}/bin/frontend/"
        fi
    fi
    if [[ ! -f "${FE_OUTPUT}/server/index.mjs" ]]; then
        error "前端构建产物缺失! 请检查 build_frontend 是否成功"
        error "预期路径: ${FE_OUTPUT}/server/index.mjs"
        exit 1
    fi
    info "前端产物验证通过: ${FE_OUTPUT}/server/index.mjs"

    # 确保 .env 在前端工作目录
    if [[ ! -f "${FE_OUTPUT}/.env" ]]; then
        cp -f "${INSTALL_DIR}/apps/frontend/.env" "${FE_OUTPUT}/.env"
    fi
    cat > /etc/systemd/system/bbsmc-frontend.service <<EOF
[Unit]
Description=BBSMC Frontend (Nuxt)
After=network.target bbsmc-labrinth.service

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}/bin/frontend/.output
Environment=NODE_ENV=production
Environment=PORT=${FRONTEND_PORT}
Environment=HOST=127.0.0.1
ExecStart=$(which node) ${INSTALL_DIR}/bin/frontend/.output/server/index.mjs
Restart=always
RestartSec=5
StandardOutput=append:/var/log/bbsmc-frontend.log
StandardError=append:/var/log/bbsmc-frontend.log

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable bbsmc-frontend
    systemctl restart bbsmc-frontend
    sleep 3
    systemctl --no-pager status bbsmc-labrinth --no-pager | head -n 15 || true
    systemctl --no-pager status bbsmc-frontend --no-pager | head -n 15 || true
    info "Systemd 服务配置完成"
}

# ---------------------- Nginx 重复 MIME 类型清理 ----------------------
cleanup_duplicate_mime() {
    local NGINX_CONF_DIR="${1:-/www/server/panel/vhost/nginx}"
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")

    local FASTCGI_CONTENT='fastcgi_param QUERY_STRING       $query_string;
fastcgi_param REQUEST_METHOD     $request_method;
fastcgi_param CONTENT_TYPE       $content_type;
fastcgi_param CONTENT_LENGTH     $content_length;
fastcgi_param SCRIPT_FILENAME    $document_root$fastcgi_script_name;
fastcgi_param SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param PATH_INFO          $fastcgi_path_info;
fastcgi_param REQUEST_URI        $request_uri;
fastcgi_param DOCUMENT_URI       $document_uri;
fastcgi_param DOCUMENT_ROOT      $document_root;
fastcgi_param SERVER_PROTOCOL    $server_protocol;
fastcgi_param REMOTE_ADDR        $remote_addr;
fastcgi_param REMOTE_PORT        $remote_port;
fastcgi_param SERVER_ADDR        $server_addr;
fastcgi_param SERVER_PORT        $server_port;
fastcgi_param SERVER_NAME        $server_name;'

    # 如果全局 nginx.conf 已包含 mime.types, 则从 vhost 中移除重复的 include
    local nginx_main
    nginx_main=$("${nginx_bin}" -V 2>&1 | grep -oP '\-\-conf-path=\K[^ ]+' 2>/dev/null || echo "/etc/nginx/nginx.conf")

    local global_has_mime=0
    if [[ -f "${nginx_main}" ]] && grep -q "mime.types" "${nginx_main}" 2>/dev/null; then
        global_has_mime=1
    fi

    # 遍历所有配置目录
    local nginx_config_dirs=("${NGINX_CONF_DIR}" "/etc/nginx/conf.d")
    for dir in "${nginx_config_dirs[@]}"; do
        [[ -d "${dir}" ]] || continue

        for conf in "${dir}"/*.conf; do
            [[ -f "${conf}" ]] || continue

            # 1. 清理重复的 mime.types 引用
            if [[ ${global_has_mime} -eq 1 ]] && grep -q "mime.types" "${conf}" 2>/dev/null; then
                warn "  清理 ${conf} 中的重复 mime.types 引用"
                sed -i '/include.*mime\.types/d' "${conf}" 2>/dev/null || true
            fi

            # 2. 清理不存在的 include 文件 (如 fastcgi_params)
            while IFS= read -r line; do
                local inc_file
                inc_file=$(echo "${line}" | grep -oP 'include\s+\K[^;]+' 2>/dev/null | tr -d ' ')
                [[ -z "${inc_file}" ]] && continue
                [[ "${inc_file}" == *"*"* ]] && continue
                [[ "${inc_file}" == *'$'* ]] && continue

                if [[ ! -f "${inc_file}" ]]; then
                    warn "  ${conf}: 引用的文件不存在: ${inc_file}"
                    local basename_inc
                    basename_inc=$(basename "${inc_file}")
                    case "${basename_inc}" in
                        fastcgi_params|fastcgi.conf|scgi_params|uwsgi_params)
                            if [[ ! -f "${inc_file}" ]]; then
                                warn "    创建 ${inc_file} 占位文件"
                                /bin/mkdir -p "$(dirname "${inc_file}")" 2>/dev/null || true
                                printf '%s\n' "${FASTCGI_CONTENT}" > "${inc_file}" 2>/dev/null || true
                            fi
                            ;;
                        *)
                            local escaped_file
                            escaped_file=$(echo "${inc_file}" | sed 's/[.[\*^$+?{|()]/\\&/g')
                            sed -i "/include.*${escaped_file}/d" "${conf}" 2>/dev/null || true
                            ;;
                    esac
                fi
            done < <(grep -n "include.*fastcgi\|include.*conf/" "${conf}" 2>/dev/null || true)

            # 3. 清理重复的 MIME 类型定义 (如重复的 types { ... } 块)
            local mime_blocks
            mime_blocks=$(grep -c 'types[[:space:]]*{' "${conf}" 2>/dev/null || echo "0")
            if [[ "${mime_blocks}" -gt 1 ]]; then
                warn "  ${conf}: 存在 ${mime_blocks} 个 types 块, 清理重复的"
                # 保留第一个 types 块, 删除后续的
                awk '/types[[:space:]]*\{/{if(++count>1){skip=1}} skip && /\}/{skip=0; next} {print}' "${conf}" > "${conf}.tmp" 2>/dev/null && /bin/mv -f "${conf}.tmp" "${conf}" 2>/dev/null || true
            fi

            # 4. 删除空行 (清理掉被删掉 include 后的空行)
            sed -i '/^[[:space:]]*$/N;/^\n$/d' "${conf}" 2>/dev/null || true
        done
    done

    # 5. 确保 /etc/nginx/fastcgi_params 存在 (全局兜底)
    if [[ ! -f "/etc/nginx/fastcgi_params" ]]; then
        warn "创建全局 /etc/nginx/fastcgi_params"
        /bin/mkdir -p /etc/nginx 2>/dev/null || true
        printf '%s\n' "${FASTCGI_CONTENT}" > "/etc/nginx/fastcgi_params" 2>/dev/null || true
    fi

    # 6. 确保 /etc/nginx/fastcgi.conf 存在
    if [[ ! -f "/etc/nginx/fastcgi.conf" ]]; then
        warn "创建全局 /etc/nginx/fastcgi.conf"
        /bin/mkdir -p /etc/nginx 2>/dev/null || true
        printf '%s\n' "${FASTCGI_CONTENT}" > "/etc/nginx/fastcgi.conf" 2>/dev/null || true
    fi

    return 0
}

# ---------------------- Nginx 问题配置清理 ----------------------
# 清理宝塔生成的 php-fpm 状态配置等可能引起问题的文件
cleanup_problematic_configs() {
    local NGINX_CONF_DIR="${1:-/www/server/panel/vhost/nginx}"

    [[ -d "${NGINX_CONF_DIR}" ]] || return 0

    # 确保 fastcgi_params 等基础文件存在 (全局兜底, 先创建再清理)
    local FASTCGI_CONTENT='fastcgi_param QUERY_STRING       $query_string;
fastcgi_param REQUEST_METHOD     $request_method;
fastcgi_param CONTENT_TYPE       $content_type;
fastcgi_param CONTENT_LENGTH     $content_length;
fastcgi_param SCRIPT_FILENAME    $document_root$fastcgi_script_name;
fastcgi_param SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param PATH_INFO          $fastcgi_path_info;
fastcgi_param REQUEST_URI        $request_uri;
fastcgi_param DOCUMENT_URI       $document_uri;
fastcgi_param DOCUMENT_ROOT      $document_root;
fastcgi_param SERVER_PROTOCOL    $server_protocol;
fastcgi_param REMOTE_ADDR        $remote_addr;
fastcgi_param REMOTE_PORT        $remote_port;
fastcgi_param SERVER_ADDR        $server_addr;
fastcgi_param SERVER_PORT        $server_port;
fastcgi_param SERVER_NAME        $server_name;'

    # 确保 /etc/nginx/fastcgi_params 存在
    if [[ ! -f "/etc/nginx/fastcgi_params" ]]; then
        warn "创建 /etc/nginx/fastcgi_params 占位文件"
        /bin/mkdir -p /etc/nginx 2>/dev/null || true
        printf '%s\n' "${FASTCGI_CONTENT}" > "/etc/nginx/fastcgi_params" 2>/dev/null || true
    fi

    # 确保 /etc/nginx/fastcgi.conf 存在
    if [[ ! -f "/etc/nginx/fastcgi.conf" ]]; then
        warn "创建 /etc/nginx/fastcgi.conf 占位文件"
        /bin/mkdir -p /etc/nginx 2>/dev/null || true
        printf '%s\n' "${FASTCGI_CONTENT}" > "/etc/nginx/fastcgi.conf" 2>/dev/null || true
    fi

    # 遍历所有 Nginx 配置目录 (vhost + conf.d)
    local nginx_config_dirs=("${NGINX_CONF_DIR}" "/etc/nginx/conf.d")
    for dir in "${nginx_config_dirs[@]}"; do
        [[ -d "${dir}" ]] || continue

        # 已知问题文件列表
        local problematic_files=(
            "phpfpm_status.conf"
            "php_status.conf"
            "php-fpm.conf"
            "php_status_check.conf"
        )

        for f in "${problematic_files[@]}"; do
            local conf="${dir}/${f}"
            if [[ -f "${conf}" ]]; then
                warn "发现问题配置 ${conf}, 重命名为 .disabled"
                /bin/mv -f "${conf}" "${conf}.disabled" 2>/dev/null || true
            fi
        done

        # 检查所有 .conf 文件中的 include 是否引用了不存在的文件
        for conf in "${dir}"/*.conf; do
            [[ -f "${conf}" ]] || continue

            # 逐行扫描 include (跳过注释行, 正确提取路径)
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                [[ "${line}" =~ ^[[:space:]]*# ]] && continue

                local inc_path
                inc_path=$(echo "${line}" | grep -oP 'include\s+\K[^;]+' 2>/dev/null | head -1 | tr -d ' ')
                [[ -z "${inc_path}" ]] && continue
                [[ "${inc_path}" == *"*"* ]] && continue
                [[ "${inc_path}" == *'$'* ]] && continue

                if [[ ! -f "${inc_path}" ]]; then
                    local basename_inc
                    basename_inc=$(basename "${inc_path}")
                    case "${basename_inc}" in
                        fastcgi_params|fastcgi.conf|scgi_params|uwsgi_params)
                            if [[ ! -f "${inc_path}" ]]; then
                                warn "创建 ${inc_path} 占位文件"
                                /bin/mkdir -p "$(dirname "${inc_path}")" 2>/dev/null || true
                                printf '%s\n' "${FASTCGI_CONTENT}" > "${inc_path}" 2>/dev/null || true
                            fi
                            ;;
                        *)
                            warn "  ${conf} 引用不存在的文件: ${inc_path}, 注释掉"
                            local escaped_path
                            escaped_path=$(echo "${inc_path}" | sed 's/[.[\*^$+?{|()]/\\&/g')
                            sed -i "s|^[[:space:]]*include ${escaped_path}|# include ${escaped_path} # disabled by BBSMC deploy|" "${conf}" 2>/dev/null || true
                            ;;
                    esac
                fi
            done < <(grep -n 'include[[:space:]]' "${conf}" 2>/dev/null || true)
        done
    done

    return 0
}

# ---------------------- Nginx 强制修复兜底 ----------------------
# 当 nginx -t 失败时, 尝试各种手段修复
fix_nginx_force_recovery() {
    local NGINX_CONF_DIR="${1:-/www/server/panel/vhost/nginx}"
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")

    local FASTCGI_CONTENT='fastcgi_param QUERY_STRING       $query_string;
fastcgi_param REQUEST_METHOD     $request_method;
fastcgi_param CONTENT_TYPE       $content_type;
fastcgi_param CONTENT_LENGTH     $content_length;
fastcgi_param SCRIPT_FILENAME    $document_root$fastcgi_script_name;
fastcgi_param SCRIPT_NAME        $fastcgi_script_name;
fastcgi_param PATH_INFO          $fastcgi_path_info;
fastcgi_param REQUEST_URI        $request_uri;
fastcgi_param DOCUMENT_ROOT      $document_root;
fastcgi_param SERVER_PROTOCOL    $server_protocol;
fastcgi_param REMOTE_ADDR        $remote_addr;
fastcgi_param REMOTE_PORT        $remote_port;
fastcgi_param SERVER_ADDR        $server_addr;
fastcgi_param SERVER_PORT        $server_port;
fastcgi_param SERVER_NAME        $server_name;'

    warn "执行 Nginx 强制修复..."

    # 1. 确保所有必要的目录存在
    /bin/mkdir -p /etc/nginx/conf.d 2>/dev/null || true
    /bin/mkdir -p "${NGINX_CONF_DIR}" 2>/dev/null || true

    # 2. 确保 fastcgi_params/fastcgi.conf 存在
    if [[ ! -f "/etc/nginx/fastcgi_params" ]]; then
        warn "创建 /etc/nginx/fastcgi_params"
        printf '%s\n' "${FASTCGI_CONTENT}" > "/etc/nginx/fastcgi_params" 2>/dev/null || true
    fi
    if [[ ! -f "/etc/nginx/fastcgi.conf" ]]; then
        warn "创建 /etc/nginx/fastcgi.conf"
        printf '%s\n' "${FASTCGI_CONTENT}" > "/etc/nginx/fastcgi.conf" 2>/dev/null || true
    fi

    # 3. 处理 phpfpm_status.conf 等问题文件
    for dir in "${NGINX_CONF_DIR}" "/etc/nginx/conf.d"; do
        [[ -d "${dir}" ]] || continue
        for problematic in phpfpm_status.conf php_status.conf php-fpm.conf php_status_check.conf; do
            if [[ -f "${dir}/${problematic}" ]]; then
                warn "禁用问题配置: ${dir}/${problematic}"
                /bin/mv -f "${dir}/${problematic}" "${dir}/${problematic}.disabled" 2>/dev/null || true
            fi
        done
    done

    # 4. 扫描所有配置, 修复不存在的 include 引用
    for dir in "${NGINX_CONF_DIR}" "/etc/nginx/conf.d"; do
        [[ -d "${dir}" ]] || continue
        for conf in "${dir}"/*.conf; do
            [[ -f "${conf}" ]] || continue

            # 处理 fastcgi_params 等引用
            while IFS= read -r line; do
                [[ -z "${line}" ]] && continue
                [[ "${line}" =~ ^[[:space:]]*# ]] && continue

                local inc_path
                inc_path=$(echo "${line}" | grep -oP 'include\s+\K[^;]+' 2>/dev/null | head -1 | tr -d ' ')
                [[ -z "${inc_path}" ]] && continue
                [[ "${inc_path}" == *"*"* ]] && continue
                [[ "${inc_path}" == *'$'* ]] && continue

                if [[ ! -f "${inc_path}" ]]; then
                    local basename_inc
                    basename_inc=$(basename "${inc_path}")
                    case "${basename_inc}" in
                        fastcgi_params|fastcgi.conf|scgi_params|uwsgi_params)
                            if [[ ! -f "${inc_path}" ]]; then
                                warn "创建缺失文件: ${inc_path}"
                                /bin/mkdir -p "$(dirname "${inc_path}")" 2>/dev/null || true
                                printf '%s\n' "${FASTCGI_CONTENT}" > "${inc_path}" 2>/dev/null || true
                            fi
                            ;;
                        *)
                            warn "注释掉无效 include: ${inc_path}"
                            local escaped_path
                            escaped_path=$(echo "${inc_path}" | sed 's/[.[\*^$+?{|()]/\\&/g')
                            sed -i "s|^[[:space:]]*include ${escaped_path}|# include ${escaped_path} # disabled by BBSMC deploy|" "${conf}" 2>/dev/null || true
                            ;;
                    esac
                fi
            done < <(grep -n 'include[[:space:]]' "${conf}" 2>/dev/null || true)
        done
    done

    # 5. 再次测试
    local test_output
    test_output=$("${nginx_bin}" -t 2>&1) || true
    if echo "${test_output}" | grep -q "successful"; then
        info "强制修复成功!"
        return 0
    fi

    # 6. 如果还是失败, 创建最小化配置确保 nginx 能启动
    warn "配置仍有错误, 创建最小化配置..."
    for dir in "${NGINX_CONF_DIR}" "/etc/nginx/conf.d"; do
        [[ -d "${dir}" ]] || continue
        # 禁用所有非 BBSMC 配置
        for conf in "${dir}"/*.conf; do
            [[ -f "${conf}" ]] || continue
            local bn
            bn=$(basename "${conf}" .conf)
            # 保留 BBSMC 相关配置
            if [[ "${bn}" == *"bbsmc"* ]] || [[ "${bn}" == _* ]]; then
                continue
            fi
            warn "临时禁用: ${conf}"
            /bin/mv -f "${conf}" "${conf}.disabled" 2>/dev/null || true
        done
    done

    # 7. 最终测试
    test_output=$("${nginx_bin}" -t 2>&1) || true
    if echo "${test_output}" | grep -q "successful"; then
        info "最小化配置修复成功!"
        return 0
    fi

    # 8. 终极方案: 完全重启 Nginx 忽略配置错误
    warn "配置仍有错误, 尝试强制启动 Nginx..."
    /bin/mkdir -p /etc/nginx/conf.d 2>/dev/null || true
    touch /etc/nginx/conf.d/default.conf 2>/dev/null || true
    "${nginx_bin}" 2>/dev/null || systemctl start nginx 2>/dev/null || true

    if pgrep -x nginx > /dev/null 2>&1; then
        warn "Nginx 已启动 (可能使用默认配置, 请手动修复)"
        return 0
    fi

    error "Nginx 启动失败, 请手动检查配置: nginx -t"
}

# ---------------------- Nginx 版本检测 ----------------------
# 设置全局变量 NGINX_VERSION, NGINX_MAJOR, NGINX_MINOR, NGINX_PATCH
# 以及 NGINX_SUPPORTS_HTTP2_DIRECTIVE, NGINX_DEPRECATED_SSL_CIPHERS
detect_nginx_version() {
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")

    NGINX_VERSION=$("${nginx_bin}" -v 2>&1 | grep -oP 'nginx/\K[0-9]+\.[0-9]+\.[0-9]+' 2>/dev/null || echo "0.0.0")
    NGINX_MAJOR=$(echo "${NGINX_VERSION}" | cut -d. -f1)
    NGINX_MINOR=$(echo "${NGINX_VERSION}" | cut -d. -f2)
    NGINX_PATCH=$("${nginx_bin}" -v 2>&1 | grep -oP '\-\-patch=\K[0-9]+' 2>/dev/null || echo "0")

    NGINX_SUPPORTS_HTTP2_DIRECTIVE=0
    if [[ -n "${NGINX_MAJOR}" && "${NGINX_MAJOR}" != "0" ]]; then
        if [[ ${NGINX_MAJOR} -gt 1 ]] || [[ ${NGINX_MAJOR} -eq 1 && ${NGINX_MINOR} -ge 25 ]]; then
            if [[ ${NGINX_MINOR} -ge 25 && ${NGINX_PATCH} -ge 1 ]] || [[ ${NGINX_MAJOR} -gt 1 ]] || [[ ${NGINX_MINOR} -gt 25 ]]; then
                NGINX_SUPPORTS_HTTP2_DIRECTIVE=1
            fi
        fi
    fi

    NGINX_DEPRECATED_SSL_CIPHERS=0
    if [[ ${NGINX_MAJOR} -ge 2 ]] || [[ ${NGINX_MAJOR} -eq 1 && ${NGINX_MINOR} -ge 30 ]]; then
        NGINX_DEPRECATED_SSL_CIPHERS=1
    fi

    if [[ "${NGINX_VERSION}" != "0.0.0" ]]; then
        info "检测到 nginx 版本: ${NGINX_VERSION} (http2_directive=${NGINX_SUPPORTS_HTTP2_DIRECTIVE}, deprecated_ssl_ciphers=${NGINX_DEPRECATED_SSL_CIPHERS})"
    fi
}

# ---------------------- Nginx SSL/HTTP2 版本适配 ----------------------
fix_nginx_http2_compat() {
    local NGINX_CONF_DIR="${1:-/www/server/panel/vhost/nginx}"

    # 使用共享的版本检测
    detect_nginx_version

    if [[ -z "${NGINX_MAJOR}" ]] || [[ "${NGINX_MAJOR}" == "0" ]]; then
        warn "无法检测 nginx 版本, 默认不处理 http2 兼容"
        return 0
    fi

    local total_fixed=0
    local conf_dirs=("${NGINX_CONF_DIR}")

    # 也处理 conf.d 目录
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")
    local nginx_conf_base
    nginx_conf_base=$(/usr/bin/dirname "$("${nginx_bin}" -V 2>&1 | grep -oP '\-\-conf-path=\K[^ ]+' 2>/dev/null || echo "/etc/nginx/nginx.conf")")
    local conf_d="${nginx_conf_base}/conf.d"
    [[ -d "${conf_d}" ]] && conf_dirs+=("${conf_d}")

    for dir in "${conf_dirs[@]}"; do
        [[ -d "${dir}" ]] || continue
        for conf in "${dir}"/*.conf; do
            [[ -f "${conf}" ]] || continue

            local needs_fix=0

            if [[ ${NGINX_SUPPORTS_HTTP2_DIRECTIVE} -eq 1 ]]; then
                # === 新 nginx (>= 1.25.1): 旧语法 → 新语法 ===
                # 将 listen 443 ssl http2; 转换为 listen 443 ssl; + http2 on;
                if grep -qE 'listen[[:space:]]+443.*http2' "${conf}" 2>/dev/null; then
                    needs_fix=1
                    warn "  修复 ${conf}: 转换旧 http2 语法 -> 新语法"
                    /bin/cp -f "${conf}" "${conf}.http2bak" 2>/dev/null || true

                    # 将 listen 443 ssl http2; 改为 listen 443 ssl; (移除 http2 参数)
                    sed -i 's/\(listen[[:space:]]\+443.*ssl\)[[:space:]]\+http2\(.*\);/\1\2;/g' "${conf}" 2>/dev/null || true

                    # 在第一个 server 块的 } 前添加 http2 on; (如果尚未存在)
                    if ! grep -qE '^\s*http2\s+on\s*;' "${conf}" 2>/dev/null; then
                        # 在 ssl_session_timeout 行后添加 http2 on; (更可靠的位置)
                        if grep -q "ssl_session_timeout" "${conf}" 2>/dev/null; then
                            sed -i '/ssl_session_timeout/a\    http2 on;' "${conf}" 2>/dev/null || true
                        elif grep -q "ssl_certificate_key" "${conf}" 2>/dev/null; then
                            sed -i '/ssl_certificate_key/a\    http2 on;' "${conf}" 2>/dev/null || true
                        else
                            # 在 listen 443 行后添加
                            sed -i '/listen[[:space:]]\+443.*ssl/a\    http2 on;' "${conf}" 2>/dev/null || true
                        fi
                    fi
                    info "    ${conf} 已转换为新 http2 语法"
                fi

                # 移除 ssl_prefer_server_ciphers (nginx >= 1.30 弃用)
                if [[ ${NGINX_DEPRECATED_SSL_CIPHERS} -eq 1 ]] && grep -q "ssl_prefer_server_ciphers" "${conf}" 2>/dev/null; then
                    needs_fix=1
                    warn "  修复 ${conf}: 移除已弃用的 ssl_prefer_server_ciphers"
                    sed -i '/ssl_prefer_server_ciphers/d' "${conf}" 2>/dev/null || true
                fi

                # 移除 ssl_ciphers (nginx >= 1.30 推荐使用 Mozilla 预设或直接移除)
                # 注意: ssl_ciphers 本身未被弃用, 但我们的硬编码值可能不再推荐
            else
                # === 旧 nginx (< 1.25.1): 新语法 → 旧语法 ===
                # 将 http2 on; / http2 off; 转换到 listen 行
                if grep -qE '^\s*http2\s+on\s*;' "${conf}" 2>/dev/null || \
                   grep -qE '^\s*http2\s+off\s*;' "${conf}" 2>/dev/null || \
                   grep -qE '^\s*http2\s*;' "${conf}" 2>/dev/null || \
                   grep -qE '^\s*http2\s+[a-zA-Z0-9]+\s*;' "${conf}" 2>/dev/null; then
                    needs_fix=1
                    warn "  修复 ${conf}: 转换新 http2 语法 -> 旧语法"
                    /bin/cp -f "${conf}" "${conf}.http2bak" 2>/dev/null || true

                    # 如果存在 http2 on;, 将 http2 合并到 listen 443 行
                    if grep -qE '^\s*http2\s+on\s*;' "${conf}" 2>/dev/null; then
                        if grep -qE 'listen[[:space:]]+443.*ssl' "${conf}" 2>/dev/null && \
                           ! grep -qE 'listen[[:space:]]+443.*http2' "${conf}" 2>/dev/null; then
                            sed -i 's/\(listen[[:space:]]\+443[[:space:]]\+ssl\);/\1 http2;/g' "${conf}" 2>/dev/null || true
                            info "    将 http2 合并到 listen 443 ssl 行"
                        fi
                    fi

                    # 移除所有独立 http2 指令行
                    sed -i '/^[[:space:]]*http2[[:space:]]*on[[:space:]]*;/d' "${conf}" 2>/dev/null || true
                    sed -i '/^[[:space:]]*http2[[:space:]]*off[[:space:]]*;/d' "${conf}" 2>/dev/null || true
                    sed -i '/^[[:space:]]*http2[[:space:]]*443[[:space:]]*;/d' "${conf}" 2>/dev/null || true
                    sed -i '/^[[:space:]]*http2[[:space:]]*;/d' "${conf}" 2>/dev/null || true
                    sed -i '/^[[:space:]]*http2[[:space:]]\+[a-zA-Z][a-zA-Z0-9_]*[[:space:]]*;/d' "${conf}" 2>/dev/null || true

                    info "    ${conf} 已转换为旧 http2 语法"
                fi
            fi

            [[ ${needs_fix} -eq 1 ]] && total_fixed=$((total_fixed + 1))
        done
    done

    if [[ ${total_fixed} -gt 0 ]]; then
        info "http2/SSL 兼容性修复完成 (nginx ${NGINX_VERSION}, 共修复 ${total_fixed} 个文件)"
    else
        info "nginx ${NGINX_VERSION} 配置已兼容 (无需 http2/SSL 修复)"
    fi
    return 0
}

# ---------------------- Nginx QUIC 指令清理 ----------------------
# nginx < 1.25.1 不支持 quic 参数, 移除它
# 同时修复之前被损坏的配置文件
fix_quic_and_corrupted() {
    local NGINX_CONF_DIR="${1:-/www/server/panel/vhost/nginx}"
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")

    detect_nginx_version

    [[ -d "${NGINX_CONF_DIR}" ]] || return 0

    for conf in "${NGINX_CONF_DIR}"/*.conf; do
        [[ -f "${conf}" ]] || continue
        local needs_fix=0

        # 1. 移除 quic 参数 (nginx < 1.25.1 不支持)
        if [[ ${NGINX_MAJOR} -lt 2 ]] && [[ ${NGINX_MINOR} -lt 25 ]]; then
            if grep -q 'quic' "${conf}" 2>/dev/null; then
                needs_fix=1
                warn "  ${conf}: 移除 quic 参数 (nginx ${NGINX_VERSION} 不支持)"
                # 移除 listen 行中的 quic 单词
                sed -i 's/\(listen[[:space:]]\+[^;]*\)[[:space:]]\+quic/\1/g' "${conf}" 2>/dev/null || true
                # 移除独立的 quic 指令行
                sed -i '/^[[:space:]]*quic[[:space:]]*on[[:space:]]*;/d' "${conf}" 2>/dev/null || true
                sed -i '/^[[:space:]]*quic[[:space:]]*;/d' "${conf}" 2>/dev/null || true
            fi
        fi

        # 2. 修复被之前损坏的配置文件 (之前 cleanup 脚本错误注释导致的)
        # 检查是否有损坏的注释行: "# include # disabled by BBSMC deploy" (路径为空)
        if grep -q '# include # disabled by BBSMC deploy' "${conf}" 2>/dev/null; then
            needs_fix=1
            warn "  ${conf}: 恢复被损坏的配置行"
            # 删除空的损坏注释行
            sed -i '/# include # disabled by BBSMC deploy/d' "${conf}" 2>/dev/null || true
        fi

        # 3. 恢复被错误注释掉的有效 include (如果注释中包含有效路径)
        # 格式: "# include /path/to/file # disabled by BBSMC deploy"
        # 恢复为: "include /path/to/file;"
        while IFS= read -r badline; do
            local goodpath
            goodpath=$(echo "${badline}" | grep -oP '# include\s+\K[^#]+' 2>/dev/null | tr -d ' ')
            if [[ -n "${goodpath}" ]] && [[ -f "${goodpath}" ]]; then
                warn "  ${conf}: 恢复 include ${goodpath}"
                # 将注释行恢复为正常的 include
                local escaped_path
                escaped_path=$(echo "${goodpath}" | sed 's/[.[\*^$+?{|()]/\\&/g')
                sed -i "s|# include ${escaped_path} # disabled by BBSMC deploy|include ${goodpath};|" "${conf}" 2>/dev/null || true
            else
                # 文件不存在, 直接删除这行 (保持注释)
                sed -i "s|# include ${escaped_path} # disabled by BBSMC deploy||" "${conf}" 2>/dev/null || true
            fi
        done < <(grep 'disabled by BBSMC deploy' "${conf}" 2>/dev/null || true)

        # 4. 清理空行 (删除因恢复/删除操作留下的空行)
        if [[ ${needs_fix} -eq 1 ]]; then
            # 删除多余空行 (连续两个及以上空行)
            sed -i '/^[[:space:]]*$/{ N; /^\n$/D; }' "${conf}" 2>/dev/null || true
            # 也删除以空格开头的空行
            sed -i '/^[[:space:]]*$/d' "${conf}" 2>/dev/null || true
        fi
    done
}

# ---------------------- Nginx 域名匹配配置管理 ----------------------
# 禁用不在域名列表中的配置文件
disable_unknown_domain_configs() {
    local NGINX_CONF_DIR="${1:-/www/server/panel/vhost/nginx}"
    local DOMAIN="${2:-}"
    local API_DOMAIN="${3:-}"
    local CDN_DOMAIN="${4:-}"

    [[ -d "${NGINX_CONF_DIR}" ]] || return 0

    # 构建允许的域名列表
    local allowed_domains=()
    [[ -n "${DOMAIN}" ]] && allowed_domains+=("${DOMAIN}")
    [[ -n "${API_DOMAIN}" ]] && allowed_domains+=("${API_DOMAIN}")
    [[ -n "${CDN_DOMAIN}" ]] && allowed_domains+=("${CDN_DOMAIN}")

    # 遍历所有 .conf 文件
    for conf in "${NGINX_CONF_DIR}"/*.conf; do
        [[ -f "${conf}" ]] || continue
        local basename
        basename=$(basename "${conf}" .conf)

        # 跳过系统配置 (以 _ 开头, 或以 0. 开头)
        [[ "${basename}" == _* ]] && continue
        [[ "${basename}" == "0."* ]] && continue

        # 跳过宝塔系统配置
        local bn="${basename}"
        [[ "${bn}" == "phpfpm_status" ]] && continue
        [[ "${bn}" == "php_status" ]] && continue
        [[ "${bn}" == "nginx_status" ]] && continue
        [[ "${bn}" == "default" ]] && continue

        # 检查是否为允许的域名
        local is_allowed=0
        for domain in "${allowed_domains[@]}"; do
            if [[ "${bn}" == "${domain}" ]]; then
                is_allowed=1
                break
            fi
        done

        # 如果不是允许的域名, 且不是系统配置, 禁用它
        if [[ ${is_allowed} -eq 0 ]] && [[ ${#allowed_domains[@]} -gt 0 ]]; then
            warn "  禁用未使用的域名配置: ${conf}"
            mv -f "${conf}" "${conf}.disabled" 2>/dev/null || true
        fi
    done
}
setup_nginx() {
    step "配置 Nginx 反向代理 (宝塔)"

    # 自动检测宝塔 nginx 配置路径
    local NGINX_CONF_DIR="/www/server/panel/vhost/nginx"
    local NGINX_MAIN=""
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")

    # 查找实际的 nginx.conf (用 nginx -V 获取真实 conf-path)
    local nginx_real_conf
    nginx_real_conf=$("${nginx_bin}" -V 2>&1 | grep -oP '\-\-conf-path=\K[^ ]+' 2>/dev/null)
    if [[ -n "${nginx_real_conf}" && -f "${nginx_real_conf}" ]]; then
        NGINX_MAIN="${nginx_real_conf}"
    elif [[ -f "/etc/nginx/nginx.conf" ]]; then
        NGINX_MAIN="/etc/nginx/nginx.conf"
    elif [[ -f "/www/server/nginx/conf/nginx.conf" ]]; then
        NGINX_MAIN="/www/server/nginx/conf/nginx.conf"
    else
        NGINX_MAIN="/etc/nginx/nginx.conf"
        warn "未找到 nginx.conf, 将创建默认配置"
    fi
    info "nginx.conf 路径: ${NGINX_MAIN}"

    # 如果 nginx.conf 缺少 events 块, 自动修复
    if [[ -f "${NGINX_MAIN}" ]] && ! grep -q "events[[:space:]]*{" "${NGINX_MAIN}" 2>/dev/null; then
        warn "${NGINX_MAIN} 缺少 events 块, 尝试修复"
        [[ -f "${NGINX_MAIN}" ]] && /bin/cp -f "${NGINX_MAIN}" "${NGINX_MAIN}.bak.$(date +%s)" 2>/dev/null || true
        if [[ -f "/www/server/nginx/conf/nginx.conf" ]] && grep -q "events[[:space:]]*{" "/www/server/nginx/conf/nginx.conf" 2>/dev/null && [[ "${NGINX_MAIN}" != "/www/server/nginx/conf/nginx.conf" ]]; then
            warn "从 /www/server/nginx/conf/nginx.conf 恢复"
            /bin/cp -f "/www/server/nginx/conf/nginx.conf" "${NGINX_MAIN}" 2>/dev/null || true
        else
            warn "创建最小 nginx.conf (已备份原文件)"
            local mime_path="/etc/nginx/mime.types"
            [[ -f "${mime_path}" ]] || mime_path="/www/server/nginx/conf/mime.types"
            [[ -f "${mime_path}" ]] || mime_path="/www/server/nginx/conf/nginx_mime_types.conf"
            [[ -f "${mime_path}" ]] || mime_path=""
            local mime_include=""
            [[ -n "${mime_path}" ]] && mime_include="include ${mime_path};"
            cat > "${NGINX_MAIN}" << NGINXDEFAULT
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    ${mime_include}
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    include /etc/nginx/conf.d/*.conf;
    include /www/server/panel/vhost/nginx/*.conf;
}
NGINXDEFAULT
        fi
    fi

    # ====== 关键修复: 强制确保 nginx.conf include vhost 目录 ======
    if [[ -f "${NGINX_MAIN}" ]]; then
        # 移除旧的 vhost include (避免重复), 再添加我们的
        sed -i '/include.*vhost.*nginx/d' "${NGINX_MAIN}" 2>/dev/null || true
        # 在 http { 后添加 include
        sed -i '/http {/a\    include /www/server/panel/vhost/nginx/*.conf;' "${NGINX_MAIN}"
        info "已确保 nginx.conf include vhost 目录"
    fi

    # 0. 确保必要目录存在
    local nginx_conf_base
    nginx_conf_base=$(/usr/bin/dirname "${NGINX_MAIN}")
    local conf_d="${nginx_conf_base}/conf.d"

    /bin/mkdir -p "${conf_d}" 2>/dev/null || true
    /bin/mkdir -p "${NGINX_CONF_DIR}" 2>/dev/null || true
    /bin/mkdir -p "${DATA_DIR}/uploads" 2>/dev/null || true

    # 0.1 创建 conf.d 占位文件
    if ! ls "${conf_d}"/*.conf >/dev/null 2>&1; then
        printf "# Auto-generated placeholder to satisfy nginx include\n" > "${conf_d}/placeholder.conf" 2>/dev/null || true
    fi

    # 1. 解析 nginx.conf 中所有 include 指令, 确保引用的文件都存在
    #    使用 sed 替代 grep -P (兼容无 Perl 正则的系统)
    if [[ -f "${NGINX_MAIN}" ]]; then
        local tmpfile
        tmpfile=$(/bin/mktemp)
        # 提取所有 include 行中的路径
        # 兼容: include path;  include  path  ;  带空格/制表符
        sed -n 's/^[[:space:]]*include[[:space:]]\+\([^;]*\)[[:space:]]*;[[:space:]]*$/\1/p' "${NGINX_MAIN}" 2>/dev/null \
            | tr -d '\r' \
            > "${tmpfile}"

        while IFS= read -r inc; do
            # 去除空格、回车、制表符
            inc="${inc//[$' \t\r']/}"
            [[ -z "${inc}" ]] && continue

            for f in ${inc}; do
                [[ -z "${f}" ]] && continue
                f="${f//\"/}"
                f="${f//\'/}"

                local dir
                dir=$(/usr/bin/dirname "${f}")
                /bin/mkdir -p "${dir}" 2>/dev/null || true

                if [[ "${f}" == *"*"* ]] || [[ "${f}" == *"?"* ]]; then
                    # 通配符: 确保目录至少有一个 .conf 文件
                    local count
                    count=$(ls "${dir}"/*.conf 2>/dev/null | wc -l)
                    if [[ ${count} -eq 0 ]]; then
                        printf "# Auto-generated placeholder for nginx wildcard include\n" > "${dir}/placeholder.conf" 2>/dev/null || true
                        info "  创建通配符占位: ${dir}/placeholder.conf"
                    fi
                else
                    # 先处理符号链接: 如果是损坏的符号链接, 必须先删除
                    if [[ -L "${f}" ]] && [[ ! -e "${f}" ]]; then
                        warn "  发现损坏的符号链接: ${f} -> $(readlink "${f}" 2>/dev/null || echo "未知")"
                        /bin/rm -f "${f}" 2>/dev/null || true
                    fi

                    # 文件不存在 (或刚删除坏链接), 创建占位文件
                    if [[ ! -e "${f}" ]]; then
                        printf "# Auto-generated placeholder for nginx include\n" > "${f}" 2>/dev/null || {
                            /bin/mkdir -p "$(/usr/bin/dirname "${f}")" 2>/dev/null || true
                            printf "# Auto-generated placeholder\n" > "${f}" 2>/dev/null || true
                        }
                        info "  创建占位: ${f}"
                    fi
                fi
            done
        done < "${tmpfile}"
        /bin/rm -f "${tmpfile}"
    fi

    # 1.5 额外兜底: 直接检测并修复常见的 modrinth.conf 缺失/损坏问题
    if [[ -f "${NGINX_MAIN}" ]] && grep -q "modrinth.conf" "${NGINX_MAIN}" 2>/dev/null; then
        /bin/mkdir -p "${conf_d}" 2>/dev/null || true
        local modrinth_conf="${conf_d}/modrinth.conf"
        # 检查 modrinth.conf 是否存在且可用
        if [[ -L "${modrinth_conf}" ]] && [[ ! -e "${modrinth_conf}" ]]; then
            warn "modrinth.conf 是损坏的符号链接, 自动删除"
            /bin/rm -f "${modrinth_conf}" 2>/dev/null || true
        fi
        if [[ ! -f "${modrinth_conf}" ]]; then
            printf "# Auto-generated placeholder for modrinth include\n" > "${modrinth_conf}" 2>/dev/null || true
            info "  修复 modrinth.conf 缺失"
        fi
    fi

    # 2.1 禁用宝塔默认 0.default.conf (它会拦截所有未匹配的请求)
    local default_conf="${NGINX_CONF_DIR}/0.default.conf"
    if [[ -f "${default_conf}" ]]; then
        warn "检测到 ${default_conf}, 重命名为 .disabled 避免拦截请求"
        /bin/mv -f "${default_conf}" "${default_conf}.disabled" 2>/dev/null || true
    fi

    # 2.1.5 清理问题配置文件 (phpfpm_status.conf 等)
    fix_quic_and_corrupted "${NGINX_CONF_DIR}"
    cleanup_problematic_configs "${NGINX_CONF_DIR}"
    disable_unknown_domain_configs "${NGINX_CONF_DIR}" "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"

    # 4. 创建 vhost 目录
    mkdir -p "${NGINX_CONF_DIR}"

    # 如果已有旧配置, 备份
    for domain in "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"; do
        local conf="${NGINX_CONF_DIR}/${domain}.conf"
        [[ -f "${conf}" && ! -f "${conf}.bak" ]] && cp "${conf}" "${conf}.bak"
    done

    # ---------- 主站 -> 前端 3000 ----------
    info "写入主站反代配置: ${DOMAIN} -> 127.0.0.1:${FRONTEND_PORT}"
    cat > "${NGINX_CONF_DIR}/${DOMAIN}.conf" <<EOFCONF
server {
    listen 80;
    server_name ${DOMAIN};
    index index.html;
    client_max_body_size 1024m;

    location / {
        proxy_pass http://127.0.0.1:${FRONTEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_buffering off;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|webp)\$ {
        proxy_pass http://127.0.0.1:${FRONTEND_PORT};
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    location ~ /\. {
        deny all;
    }
}
EOFCONF

    # ---------- API 子域名 -> 后端 8000 ----------
    info "写入 API 反代配置: ${API_DOMAIN} -> 127.0.0.1:${BACKEND_PORT}"
    cat > "${NGINX_CONF_DIR}/${API_DOMAIN}.conf" <<EOFCONF
server {
    listen 80;
    server_name ${API_DOMAIN};
    client_max_body_size 1024m;

    location / {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_buffering off;
    }
}
EOFCONF

    # ---------- CDN 子域名 -> 静态文件 ----------
    info "写入 CDN 反代配置: ${CDN_DOMAIN} -> ${DATA_DIR}/uploads"
    cat > "${NGINX_CONF_DIR}/${CDN_DOMAIN}.conf" <<EOFCONF
server {
    listen 80;
    server_name ${CDN_DOMAIN};
    root ${DATA_DIR}/uploads;
    client_max_body_size 1024m;

    location / {
        try_files \$uri \$uri/ =404;
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods 'GET, OPTIONS';
    }

    location ~* \.(jpg|jpeg|png|gif|webp|svg|ico|css|js|woff|woff2)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location ~ /\. {
        deny all;
    }
}
EOFCONF

    # ---------- 默认 catch-all server (兜底, 防止 404) ----------
    info "写入默认 server (兜底, 防止默认 404 页)"
    cat > "${NGINX_CONF_DIR}/_catch_all.conf" <<EOFCONF
server {
    listen 80 default_server;
    server_name _;
    return 301 https://${DOMAIN}\$request_uri;
}
EOFCONF

    # 测试并重载 Nginx
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")

    # 如果 nginx 未运行, 先尝试启动
    if ! pgrep -x nginx > /dev/null 2>&1; then
        warn "Nginx 未运行, 尝试启动..."
        "${nginx_bin}" 2>/dev/null || systemctl start nginx 2>/dev/null || true
        sleep 1
    fi

    # 修复 http2 指令兼容性 (宝塔默认 nginx < 1.25.1)
    fix_quic_and_corrupted "${NGINX_CONF_DIR}"
    fix_nginx_http2_compat "${NGINX_CONF_DIR}"
    cleanup_problematic_configs "${NGINX_CONF_DIR}"
    cleanup_duplicate_mime "${NGINX_CONF_DIR}"

    # 测试配置
    local nginx_test_output
    nginx_test_output=$("${nginx_bin}" -t 2>&1) || true
    echo "${nginx_test_output}"

    if echo "${nginx_test_output}" | grep -q "successful"; then
        # 配置正确, 尝试 reload 或 start
        if pgrep -x nginx > /dev/null 2>&1; then
            "${nginx_bin}" -s reload 2>/dev/null || "${nginx_bin}" 2>/dev/null || true
            info "Nginx 反代配置完成, 已 reload"
        else
            "${nginx_bin}" 2>/dev/null || systemctl start nginx 2>/dev/null || true
            info "Nginx 反代配置完成, 已 start"
        fi
    else
        warn "Nginx 配置测试失败, 输出: ${nginx_test_output}"
        warn "执行强制修复..."
        fix_nginx_force_recovery "${NGINX_CONF_DIR}"
    fi

    # 最终确认: 确保 nginx 在运行
    sleep 1
    if ! pgrep -x nginx > /dev/null 2>&1; then
        warn "Nginx 仍未运行, 使用最后手段..."
        mkdir -p "/etc/nginx/conf.d" 2>/dev/null || true
        touch "/etc/nginx/conf.d/default.conf" 2>/dev/null || true
        "${nginx_bin}" 2>/dev/null || systemctl start nginx 2>/dev/null || true
        sleep 1
    fi
    if pgrep -x nginx > /dev/null 2>&1; then
        info "Nginx 运行中 ✓"
    else
        warn "Nginx 无法启动, 请手动检查 nginx -t"
    fi
}

# ---------------------- 申请 SSL 证书 ----------------------
setup_ssl() {
    step "配置 SSL 证书"

    local BT_CLI="/etc/init.d/bt"
    local BT_PYTHON="/www/server/panel/pyenv/bin/python3"

    # 先尝试检测宝塔已有的证书
    local BT_CERT_BASE="/www/server/panel/vhost/cert"
    local certs_found=0
    for domain in "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"; do
        local cert_dir="${BT_CERT_BASE}/${domain}"
        if [[ -d "${cert_dir}" ]]; then
            local cert_file=""
            local key_file=""
            # 宝塔常见的证书文件名
            for pattern in "fullchain.pem" "${domain}_bundle.crt" "${domain}.crt"; do
                [[ -f "${cert_dir}/${pattern}" ]] && cert_file="${cert_dir}/${pattern}" && break
            done
            for pattern in "privkey.pem" "${domain}.key" "${domain}.pem"; do
                [[ -f "${cert_dir}/${pattern}" ]] && key_file="${cert_dir}/${pattern}" && break
            done
            if [[ -n "${cert_file}" && -n "${key_file}" ]]; then
                info "检测到已有 SSL 证书: ${domain} (${cert_file})"
                certs_found=$((certs_found + 1))
            fi
        fi
    done

    # 如果没有检测到现有证书, 尝试申请
    if [[ ${certs_found} -eq 0 ]]; then
        warn "未检测到 SSL 证书, 尝试通过宝塔申请..."
        if [[ ! -x "${BT_PYTHON}" ]]; then
            warn "未找到宝塔 Python, 跳过自动 SSL 申请"
            warn "请手动在宝塔面板 -> 网站 -> SSL 中申请 Let's Encrypt 证书"
            return
        fi

        apply_ssl() {
            local site_domain="$1"
            info "为 ${site_domain} 申请 SSL 证书..."
            ${BT_PYTHON} /www/server/panel/BT-Panel <<PYEOF
import sys
sys.path.insert(0, '/www/server/panel')
sys.path.insert(0, '/www/server/panel/class')
import public
try:
    import acme_v2
    acme = acme_v2.acme_v2()
    args = public.dict_obj()
    args.siteName = '${site_domain}'
    args.type = '1'
    args.dnsapi = ''
    args.domain = '${site_domain}'
    result = acme.apply_cert(args)
    print('SSL_OK: ${site_domain}')
except Exception as e:
    print('SSL_FAIL: ${site_domain} -', e)
PYEOF
        }

        apply_ssl "${DOMAIN}"
        apply_ssl "${API_DOMAIN}"
        apply_ssl "${CDN_DOMAIN}"
    else
        info "检测到 ${certs_found} 个已有 SSL 证书, 直接应用到 Nginx"
    fi

    # 自动更新 Nginx 配置添加 SSL 监听
    detect_nginx_version

    local use_new_http2=${NGINX_SUPPORTS_HTTP2_DIRECTIVE}
    local skip_prefer_ciphers=${NGINX_DEPRECATED_SSL_CIPHERS}

    if [[ ${use_new_http2} -eq 1 ]]; then
        info "使用新 http2 语法 (http2 on;) 生成 SSL 配置"
    fi
    if [[ ${skip_prefer_ciphers} -eq 1 ]]; then
        info "跳过已弃用的 ssl_prefer_server_ciphers"
    fi

    for domain in "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"; do
        local cert_dir="${BT_CERT_BASE}/${domain}"
        local cert_path=""
        local key_path=""

        # 查找证书文件 (支持多种命名格式)
        for pattern in "fullchain.pem" "${domain}_bundle.crt" "${domain}.crt"; do
            [[ -f "${cert_dir}/${pattern}" ]] && cert_path="${cert_dir}/${pattern}" && break
        done
        for pattern in "privkey.pem" "${domain}.key" "${domain}.pem"; do
            [[ -f "${cert_dir}/${pattern}" ]] && key_path="${cert_dir}/${pattern}" && break
        done

        # 如果上面没找到, 尝试遍历目录
        if [[ -z "${cert_path}" && -d "${cert_dir}" ]]; then
            cert_path=$(find "${cert_dir}" -name "*.pem" -o -name "*bundle*" -o -name "*.crt" 2>/dev/null | head -1)
            # 尝试用 openssl 验证
            if [[ -n "${cert_path}" ]] && openssl x509 -in "${cert_path}" -noout -subject 2>/dev/null; then
                info "找到证书: ${cert_path}"
            else
                cert_path=""
            fi
        fi

        if [[ -z "${key_path}" && -d "${cert_dir}" ]]; then
            key_path=$(find "${cert_dir}" -name "privkey*" -o -name "*.key" -o -name "*.pem" 2>/dev/null | head -1)
            if [[ -n "${key_path}" ]] && openssl rsa -in "${key_path}" -check -noout 2>/dev/null; then
                info "找到私钥: ${key_path}"
            else
                key_path=""
            fi
        fi

        local conf_path="/www/server/panel/vhost/nginx/${domain}.conf"

        if [[ -n "${cert_path}" && -n "${key_path}" && -f "${conf_path}" ]]; then
            # 检查配置是否已包含 SSL (宝塔 acme_v2 可能已添加)
            if ! grep -q "listen 443" "${conf_path}" 2>/dev/null; then
                info "为 ${domain} 添加 SSL 配置 (证书: ${cert_path})..."

                if [[ ${use_new_http2} -eq 1 ]]; then
                    # 新语法: listen 443 ssl; + http2 on;
                    if [[ ${skip_prefer_ciphers} -eq 1 ]]; then
                        sed -i "/listen 80;/a\\
    listen 443 ssl;\\
    ssl_certificate    ${cert_path};\\
    ssl_certificate_key ${key_path};\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;\\
    ssl_session_cache shared:SSL:10m;\\
    ssl_session_timeout 10m;\\
    http2 on;" "${conf_path}"
                    else
                        sed -i "/listen 80;/a\\
    listen 443 ssl;\\
    ssl_certificate    ${cert_path};\\
    ssl_certificate_key ${key_path};\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;\\
    ssl_prefer_server_ciphers on;\\
    ssl_session_cache shared:SSL:10m;\\
    ssl_session_timeout 10m;\\
    http2 on;" "${conf_path}"
                    fi
                else
                    # 旧语法: listen 443 ssl http2;
                    if [[ ${skip_prefer_ciphers} -eq 1 ]]; then
                        sed -i "/listen 80;/a\\
    listen 443 ssl http2;\\
    ssl_certificate    ${cert_path};\\
    ssl_certificate_key ${key_path};\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;\\
    ssl_session_cache shared:SSL:10m;\\
    ssl_session_timeout 10m;" "${conf_path}"
                    else
                        sed -i "/listen 80;/a\\
    listen 443 ssl http2;\\
    ssl_certificate    ${cert_path};\\
    ssl_certificate_key ${key_path};\\
    ssl_protocols TLSv1.2 TLSv1.3;\\
    ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:HIGH:!aNULL:!MD5:!RC4:!DHE;\\
    ssl_prefer_server_ciphers on;\\
    ssl_session_cache shared:SSL:10m;\\
    ssl_session_timeout 10m;" "${conf_path}"
                    fi
                fi
            else
                info "${domain} 已包含 SSL 配置, 跳过手动添加"
            fi
        fi
    done

    # 添加 SSL catch-all server (防止 HTTPS 请求显示证书错误)
    local catch_all_ssl="/www/server/panel/vhost/nginx/_catch_all_ssl.conf"
    local ssl_cert_path=""
    local ssl_key_path=""
    local main_cert_dir="${BT_CERT_BASE}/${DOMAIN}"
    for pattern in "fullchain.pem" "${DOMAIN}_bundle.crt" "${DOMAIN}.crt"; do
        [[ -f "${main_cert_dir}/${pattern}" ]] && ssl_cert_path="${main_cert_dir}/${pattern}" && break
    done
    [[ -f "${main_cert_dir}/privkey.pem" ]] && ssl_key_path="${main_cert_dir}/privkey.pem"
    [[ -f "${main_cert_dir}/${DOMAIN}.key" ]] && ssl_key_path="${main_cert_dir}/${DOMAIN}.key"
    if [[ -n "${ssl_cert_path}" && -n "${ssl_key_path}" ]]; then
        cat > "${catch_all_ssl}" <<EOFCONF
server {
    listen 443 ssl default_server;
    server_name _;
    ssl_certificate    ${ssl_cert_path};
    ssl_certificate_key ${ssl_key_path};
    ssl_protocols TLSv1.2 TLSv1.3;
    return 301 https://${DOMAIN}\$request_uri;
}
EOFCONF
        info "已添加 SSL catch-all server"
    fi

    nginx -t 2>/dev/null && nginx -s reload 2>/dev/null
    # SSL 配置完成后立即修复 http2 兼容性 (宝塔 acme_v2 可能写入 http2 指令)
    fix_quic_and_corrupted "/www/server/panel/vhost/nginx"
    fix_nginx_http2_compat "/www/server/panel/vhost/nginx"
    cleanup_problematic_configs "/www/server/panel/vhost/nginx"
    cleanup_duplicate_mime "/www/server/panel/vhost/nginx"
    # 测试修复后的配置
    if ! nginx -t 2>/dev/null; then
        warn "SSL 后 Nginx 配置仍有错误, 执行强制修复..."
        fix_nginx_force_recovery "/www/server/panel/vhost/nginx"
    fi
    info "SSL 配置完成 (如证书申请失败, 请手动在宝塔面板申请)"
}

# ---------------------- Modrinth 官网镜像模式 ----------------------
# 最简实现: 不改项目源码, 仅通过 Nginx 分流
#   GET  (浏览/搜索)     -> 代理到 api.modrinth.com / modrinth.com
#   POST/PUT/PATCH/DELETE (上传/修改) -> 本地 labrinth
#   本地上传的 mod 存储在本地, 不同步到官网
setup_modrinth_mirror() {
    [[ "${MIRROR_MODE}" != "1" ]] && { info "镜像模式未启用, 跳过"; return; }
    step "配置 Modrinth 官网镜像模式"

    local api_conf="/www/server/panel/vhost/nginx/${API_DOMAIN}.conf"
    local main_conf="/www/server/panel/vhost/nginx/${DOMAIN}.conf"

    # 备份非镜像模式配置
    [[ -f "${api_conf}" && ! -f "${api_conf}.nomirror" ]] && cp "${api_conf}" "${api_conf}.nomirror"
    [[ -f "${main_conf}" && ! -f "${main_conf}.nomirror" ]] && cp "${main_conf}" "${main_conf}.nomirror"

    info "重写 API 反代配置: GET -> 官网, POST -> 本地"
    cat > "${api_conf}" <<EOFCONF
# Modrinth 镜像模式 - API 反代
# GET  请求代理到 api.modrinth.com (显示官方 mod 数据)
# 写请求路由到本地 labrinth (本地上传, 不同步官网)

server {
    listen 80;
    server_name ${API_DOMAIN};

    client_max_body_size 1024m;
    client_body_buffer_size 512k;

    resolver 8.8.8.8 1.1.1.1 valid=300s ipv6=off;
    resolver_timeout 5s;

    # ====== 本地路由: 用户/认证/上传相关 (所有方法都走本地) ======
    # 匹配 v2/xxx 路径, 包括 _internal 前缀 (前端可能使用 v2/_internal/auth/xxx)
    location ~ ^/v[0-9]+/(_internal|auth|user|session|pat|oauth|notifications|report|thread|billing|payout|collections) {
        # API 兼容性重写:
        #   v2/auth/register -> v2/auth/create_account_with_password (前端可能请求 register)
        rewrite ^/v[0-9]+/auth/register$ /v2/auth/create_account_with_password break;
        #   v2/_internal/auth/xxx -> v2/auth/xxx (去掉 _internal 前缀, 匹配后端路由)
        rewrite ^/v[0-9]+/_internal/auth/(.*)$ /v2/auth/$1 break;
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host ${API_DOMAIN};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
    }

    # ====== 本地上传的 mod 详情/版本访问 (走本地 labrinth, 404 回源官网) ======
    location ~ ^/v[0-9]+/(project|version|version_file|image|mod) {
        proxy_intercept_errors on;
        error_page 404 = @modrinth_official;
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host ${API_DOMAIN};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # ====== 内部 API 路由 (健康检查/认证等, 所有方法都走本地) ======
    # 后端注册了 _internal/auth/xxx, _internal/health, _internal/admin/xxx 等路由
    # 注: v2/_internal/xxx 路径在 location ~ ^/v[0-9]+/(_internal|auth|...) 块中处理
    location /_internal/ {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host ${API_DOMAIN};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
    }

    # ====== 通用路由: 根据请求方法分流 ======
    # POST/PUT/PATCH/DELETE -> 本地 labrinth (418 -> @local_labrinth)
    # GET/HEAD/OPTIONS -> modrinth 官网 (419 -> @modrinth_official)
    # 使用 error_page + return 模式, 避免 if+proxy_pass 的各种问题
    location / {
        # 默认: GET 请求走 modrinth 官网
        error_page 418 = @local_labrinth;
        error_page 419 = @modrinth_official;

        # 写请求 -> 本地 labrinth
        if (\$request_method ~* ^(POST|PUT|PATCH|DELETE)\$) {
            return 418;
        }

        # 读请求 -> modrinth 官网
        return 419;
    }

    # ====== 本地 labrinth 命名 location (写请求目标) ======
    location @local_labrinth {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host ${API_DOMAIN};
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
    }

    # ====== 官网 modrinth 命名 location (GET 请求目标 + 本地404回源) ======
    location @modrinth_official {
        proxy_pass https://api.modrinth.com;
        proxy_set_header Host api.modrinth.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_server_name on;
        proxy_connect_timeout 30s;
        proxy_read_timeout 300s;
    }

    # 健康检查 (走本地)
    location = /_internal/health {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host ${API_DOMAIN};
    }

    location ~ /\. {
        deny all;
    }
}
EOFCONF

    info "重写主站反代配置: 前端代理到 modrinth.com (完整镜像)"
    cat > "${main_conf}" <<EOFCONF
# Modrinth 镜像模式 - 主站前端代理到官网
# 注意: API 反代使用 error_page+return 模式按请求方法分流, 避免 builder error
server {
    listen 80;
    server_name ${DOMAIN};

    client_max_body_size 1024m;

    resolver 8.8.8.8 1.1.1.1 valid=300s ipv6=off;
    resolver_timeout 5s;

    # 主站前端 -> 官网 modrinth.com (完整镜像)
    location / {
        proxy_pass https://modrinth.com;
        proxy_set_header Host modrinth.com;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_ssl_server_name on;
        proxy_connect_timeout 30s;
        proxy_read_timeout 300s;

        proxy_cookie_domain modrinth.com ${DOMAIN};
        proxy_cookie_path / /;

        sub_filter 'modrinth.com' '${DOMAIN}';
        sub_filter 'api.modrinth.com' '${API_DOMAIN}';
        sub_filter_once off;
        sub_filter_types application/javascript application/json text/html text/css;
    }

    # API 请求转发到 API 子域 (使用命名 location 避免变量化 proxy_pass)
    location /api/ {
        return 301 https://${API_DOMAIN}\$request_uri;
    }

    # CDN 资源 -> 本地 CDN (使用命名 location 避免变量化 proxy_pass)
    location /cdn/ {
        return 301 https://${CDN_DOMAIN}\$request_uri;
    }

    location ~ /\. {
        deny all;
    }
}
EOFCONF

    # 修复 http2 指令兼容性 (宝塔默认 nginx < 1.25.1)
    fix_quic_and_corrupted "/www/server/panel/vhost/nginx"
    fix_nginx_http2_compat "/www/server/panel/vhost/nginx"
    cleanup_problematic_configs "/www/server/panel/vhost/nginx"
    cleanup_duplicate_mime "/www/server/panel/vhost/nginx"

    # 测试并重载
    local nginx_test_output
    nginx_test_output=$(nginx -t 2>&1) || true
    echo "${nginx_test_output}"
    if echo "${nginx_test_output}" | grep -q "successful"; then
        nginx -s reload 2>/dev/null || nginx 2>/dev/null
        info "Modrinth 镜像模式已启用"
        info "  浏览/搜索 (GET)  -> api.modrinth.com / modrinth.com"
        info "  上传/修改 (POST) -> 本地 labrinth (127.0.0.1:${BACKEND_PORT})"
        info "  本地 mod 访问    -> 本地 labrinth (404 时回源官网)"
        info "  用户/认证        -> 本地 labrinth"
        warn "注意: 本地上传的 mod 不会出现在官网搜索结果中 (不同步官网)"
        warn "      如需禁用镜像模式, 恢复 .nomirror 备份即可"
    else
        warn "镜像模式配置测试失败, 执行强制修复..."
        fix_nginx_force_recovery "/www/server/panel/vhost/nginx"
    fi
}

# ---------------------- 防火墙 ----------------------
setup_firewall() {
    step "配置防火墙"
    ufw allow 22/tcp      || true
    ufw allow 80/tcp      || true
    ufw allow 443/tcp     || true
    ufw allow 8888/tcp    || true   # 宝塔面板默认端口
    ufw --force enable
    info "防火墙规则: 22, 80, 443, 8888 已放行"
    info "数据库端口仅绑定 127.0.0.1, 不对外暴露"
}

# ---------------------- 部署后验证 ----------------------
post_deploy_verify() {
    step "部署后验证"

    local all_ok=1

    # 1. 验证 systemd 服务状态
    info "检查 systemd 服务..."
    for svc in bbsmc-labrinth bbsmc-frontend; do
        local state
        state=$(systemctl is-active "${svc}" 2>/dev/null || echo "unknown")
        if [[ "${state}" == "active" ]]; then
            info "  ${svc}: active ✓"
        else
            warn "  ${svc}: ${state} ✗"
            warn "    查看日志: journalctl -u ${svc} -n 20 --no-pager"
            all_ok=0
        fi
    done

    # 2. 验证后端 API
    info "检查后端 API..."
    local backend_code
    backend_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${BACKEND_PORT}/v2/tag/category" 2>/dev/null || echo "000")
    if [[ "${backend_code}" == "200" ]] || [[ "${backend_code}" == "401" ]] || [[ "${backend_code}" == "403" ]]; then
        info "  后端 API (port ${BACKEND_PORT}): HTTP ${backend_code} ✓"
    else
        warn "  后端 API (port ${BACKEND_PORT}): HTTP ${backend_code} ✗"
        warn "    查看日志: tail -30 /var/log/bbsmc-labrinth.log"
        all_ok=0
    fi

    # 3. 验证前端服务
    info "检查前端服务..."
    local frontend_code
    frontend_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${FRONTEND_PORT}" 2>/dev/null || echo "000")
    if [[ "${frontend_code}" == "200" ]] || [[ "${frontend_code}" == "301" ]] || [[ "${frontend_code}" == "302" ]]; then
        info "  前端服务 (port ${FRONTEND_PORT}): HTTP ${frontend_code} ✓"
    else
        warn "  前端服务 (port ${FRONTEND_PORT}): HTTP ${frontend_code} ✗"
        warn "    查看日志: tail -30 /var/log/bbsmc-frontend.log"
        all_ok=0
    fi

    # 4. 验证 Nginx
    info "检查 Nginx..."
    local nginx_status
    nginx_status=$(systemctl is-active nginx 2>/dev/null || echo "unknown")
    if [[ "${nginx_status}" == "active" ]]; then
        info "  Nginx: active ✓"
    else
        warn "  Nginx: ${nginx_status} ✗"
        all_ok=0
    fi

    # 5. 验证 Nginx vhost 配置
    info "检查 Nginx vhost 配置..."
    for domain in "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"; do
        local conf="/www/server/panel/vhost/nginx/${domain}.conf"
        if [[ -f "${conf}" ]]; then
            info "  ${domain}: 配置存在 ✓"
        else
            warn "  ${domain}: 配置缺失 ✗"
            all_ok=0
        fi
    done

    # 6. 验证 Nginx 反代是否生效 (用 Host header 测试)
    info "检查 Nginx 反代..."
    for domain in "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"; do
        local test_code
        test_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 3 --max-time 5 \
            -H "Host: ${domain}" "http://127.0.0.1" 2>/dev/null || echo "000")
        if [[ "${test_code}" != "000" ]]; then
            info "  ${domain}: HTTP ${test_code} ✓"
        else
            warn "  ${domain}: HTTP ${test_code} ✗"
        fi
    done

    # 7. 验证 Docker 数据库
    info "检查数据库容器..."
    docker compose -f "${INSTALL_DIR}/docker-compose.prod.yml" ps 2>/dev/null || true

    # 8. 验证注册接口不再出现 reroute_error (核心回归测试)
    info "检查注册接口路由和错误模式..."
    local auth_body='{"username":"deploy_verify_user_'"$(date +%s)"'","email":"verify_'"$(date +%s)"'@example.com","password":"Verify123!@#","challenge":"deploy_verify"}'
    local auth_resp
    local auth_http
    auth_http=$(curl -s -o /tmp/bbsmc_auth_resp.json -w "%{http_code}" \
        --connect-timeout 3 --max-time 8 \
        -X POST -H "Content-Type: application/json" \
        -d "${auth_body}" \
        "http://127.0.0.1:${BACKEND_PORT}/v2/auth/create" 2>/dev/null || echo "000")
    auth_resp=""
    [[ -f /tmp/bbsmc_auth_resp.json ]] && auth_resp=$(cat /tmp/bbsmc_auth_resp.json 2>/dev/null || echo "")

    if [[ "${auth_http}" == "000" ]]; then
        warn "  注册接口 (v2/auth/create): 无法连接后端 (HTTP ${auth_http}) ✗"
        all_ok=0
    elif echo "${auth_resp}" | grep -q "reroute_error"; then
        warn "  注册接口 (v2/auth/create): 返回 reroute_error! (HTTP ${auth_http}) ✗"
        warn "    响应: ${auth_resp}"
        warn "    可能原因: 旧版本后端二进制; 需要重新 cargo build 部署最新 risk.rs 修复"
        all_ok=0
    else
        # 正常返回 (HTTP 400 用户名已存在/密码复杂度不足 也算通过)
        local rerr
        rerr=$(echo "${auth_resp}" | grep -oE '"error"\s*:\s*"[^"]+"' | head -1)
        info "  注册接口 (v2/auth/create): HTTP ${auth_http} ✓"
        if [[ -n "${rerr}" ]]; then
            info "    业务错误 (可接受): ${rerr}"
        fi
    fi
    rm -f /tmp/bbsmc_auth_resp.json 2>/dev/null || true

    echo ""
    if [[ ${all_ok} -eq 1 ]]; then
        info "所有检查通过! 部署成功!"
    else
        warn "部分检查未通过, 请查看上方日志排查"
        warn "常见问题:"
        warn "  1. 如果后端未启动: 检查 .env 文件是否在 bin/ 目录"
        warn "  2. 如果前端未启动: 检查 .output 目录是否完整"
        warn "  3. 如果 Nginx 未生效: 运行 nginx -t 检查语法"
    fi

    # 诊断: 显示 nginx 实际加载的配置
    info "Nginx 诊断信息:"
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")
    local nginx_main
    nginx_main=$("${nginx_bin}" -V 2>&1 | grep -oP '\-\-conf-path=\K[^ ]+' 2>/dev/null || echo "/etc/nginx/nginx.conf")
    echo "  nginx.conf: ${nginx_main}"
    echo "  包含的 vhost 配置:"
    local vhost_dir="/www/server/panel/vhost/nginx"
    if [[ -d "${vhost_dir}" ]]; then
        for f in "${vhost_dir}"/*.conf; do
            [[ -f "${f}" ]] || continue
            local server_names
            server_names=$(grep -oP 'server_name\s+\K[^;]+' "${f}" 2>/dev/null || echo "?")
            local ports
            ports=$(grep -oP 'listen\s+\K[^;]+' "${f}" 2>/dev/null | tr '\n' ' ' || echo "")
            echo "    $(basename "${f}"): server_name=[${server_names}] listen=[${ports}]"
        done
    fi
    echo "  nginx -t 测试:"
    "${nginx_bin}" -t 2>&1 || true
}

# ---------------------- 完成提示 ----------------------
print_summary() {
    step "部署完成"
    local mirror_status="未启用 纯本地"
    [[ "${MIRROR_MODE}" == "1" ]] && mirror_status="已启用 GET代理官网 POST本地上传"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              BBSMC 部署成功! (Deployment Success)              ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${CYAN}──────────────── 服务状态 (Service Status) ────────────────${NC}"
    echo ""

    local backend_state backend_pid backend_mem backend_uptime
    backend_state=$(systemctl is-active bbsmc-labrinth 2>/dev/null || echo "unknown")
    backend_pid=$(systemctl show -p MainPID --value bbsmc-labrinth 2>/dev/null || echo "-")
    backend_mem=$(systemctl show -p MemoryCurrent --value bbsmc-labrinth 2>/dev/null || echo "0")
    backend_uptime=$(systemctl show -p ActiveEnterTimestamp --value bbsmc-labrinth 2>/dev/null || echo "-")
    backend_mem=$(( backend_mem / 1024 / 1024 ))
    if [[ "${backend_state}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} bbsmc-labrinth (后端 API)    状态: ${GREEN}active${NC}  PID: ${backend_pid}  内存: ${backend_mem}MB"
    else
        echo -e "  ${RED}✗${NC} bbsmc-labrinth (后端 API)    状态: ${RED}${backend_state}${NC}"
    fi

    local frontend_state frontend_pid frontend_mem frontend_uptime
    frontend_state=$(systemctl is-active bbsmc-frontend 2>/dev/null || echo "unknown")
    frontend_pid=$(systemctl show -p MainPID --value bbsmc-frontend 2>/dev/null || echo "-")
    frontend_mem=$(systemctl show -p MemoryCurrent --value bbsmc-frontend 2>/dev/null || echo "0")
    frontend_mem=$(( frontend_mem / 1024 / 1024 ))
    if [[ "${frontend_state}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} bbsmc-frontend (前端 Nuxt)   状态: ${GREEN}active${NC}  PID: ${frontend_pid}  内存: ${frontend_mem}MB"
    else
        echo -e "  ${RED}✗${NC} bbsmc-frontend (前端 Nuxt)   状态: ${RED}${frontend_state}${NC}"
    fi

    local nginx_state
    nginx_state=$(systemctl is-active nginx 2>/dev/null || echo "unknown")
    if [[ "${nginx_state}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} nginx (反向代理)              状态: ${GREEN}active${NC}"
    else
        echo -e "  ${RED}✗${NC} nginx (反向代理)              状态: ${RED}${nginx_state}${NC}"
    fi

    # SSL 证书状态
    echo ""
    echo -e "${CYAN}──────────────── SSL 证书状态 ────────────────${NC}"
    echo ""
    for domain in "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"; do
        local cert_path="/www/server/panel/vhost/cert/${domain}/fullchain.pem"
        local key_path="/www/server/panel/vhost/cert/${domain}/privkey.pem"
        if [[ -f "${cert_path}" && -f "${key_path}" ]]; then
            local cert_expiry
            cert_expiry=$(openssl x509 -in "${cert_path}" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "未知")
            echo -e "  ${GREEN}✓${NC} ${domain}: 有效 (到期: ${cert_expiry})"
        else
            echo -e "  ${RED}✗${NC} ${domain}: 证书未配置"
        fi
    done

    echo ""
    echo -e "${CYAN}──────────────── Docker 容器状态 ────────────────${NC}"
    echo ""

    if command -v docker &>/dev/null; then
        ( cd "${INSTALL_DIR}" 2>/dev/null && docker compose -f docker-compose.prod.yml ps 2>/dev/null ) || \
        ( cd "${INSTALL_DIR}" 2>/dev/null && docker-compose -f docker-compose.prod.yml ps 2>/dev/null ) || \
        echo "  (Docker 容器未运行或 compose 文件不存在)"
    else
        echo "  Docker 未安装"
    fi

    echo ""
    echo -e "${CYAN}──────────────── 后端日志 (最近 10 行) ────────────────${NC}"
    echo ""
    if [[ -f /var/log/bbsmc-labrinth.log ]]; then
        sed 's/^/  /' < <(tail -10 /var/log/bbsmc-labrinth.log 2>/dev/null)
    else
        echo "  (无日志)"
    fi

    echo ""
    echo -e "${CYAN}──────────────── 前端日志 (最近 5 行) ────────────────${NC}"
    echo ""
    if [[ -f /var/log/bbsmc-frontend.log ]]; then
        sed 's/^/  /' < <(tail -5 /var/log/bbsmc-frontend.log 2>/dev/null)
    else
        echo "  (无日志)"
    fi

    echo ""
    echo -e "${CYAN}──────────────── 健康检查 (Health Check) ────────────────${NC}"
    echo ""

    local backend_code
    backend_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${BACKEND_PORT}/v2/tag/category" 2>/dev/null || echo "000")
    if [[ "${backend_code}" == "200" ]] || [[ "${backend_code}" == "401" ]] || [[ "${backend_code}" == "403" ]]; then
        echo -e "  ${GREEN}✓${NC} 后端 API (127.0.0.1:${BACKEND_PORT})     HTTP ${GREEN}${backend_code}${NC}"
    else
        echo -e "  ${RED}✗${NC} 后端 API (127.0.0.1:${BACKEND_PORT})     HTTP ${RED}${backend_code}${NC}"
    fi

    local frontend_code
    frontend_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${FRONTEND_PORT}" 2>/dev/null || echo "000")
    if [[ "${frontend_code}" == "200" ]] || [[ "${frontend_code}" == "301" ]] || [[ "${frontend_code}" == "302" ]]; then
        echo -e "  ${GREEN}✓${NC} 前端服务 (127.0.0.1:${FRONTEND_PORT})    HTTP ${GREEN}${frontend_code}${NC}"
    else
        echo -e "  ${RED}✗${NC} 前端服务 (127.0.0.1:${FRONTEND_PORT})    HTTP ${RED}${frontend_code}${NC}"
    fi

    local db_code
    db_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${MEILI_PORT}" 2>/dev/null || echo "000")
    if [[ "${db_code}" != "000" ]]; then
        echo -e "  ${GREEN}✓${NC} Meilisearch (127.0.0.1:${MEILI_PORT})     HTTP ${GREEN}${db_code}${NC}"
    else
        echo -e "  ${RED}✗${NC} Meilisearch (127.0.0.1:${MEILI_PORT})     HTTP ${RED}${db_code}${NC}"
    fi

    echo ""
    echo -e "${CYAN}──────────────── 系统信息 (System Info) ────────────────${NC}"
    echo ""

    local sys_mem
    sys_mem=$(free -m 2>/dev/null | awk '/^Mem:/ {printf "%.0fMB / %.0fMB (%.0f%%)", $3, $2, $3/$2*100}' || echo "N/A")
    echo -e "  内存:  ${sys_mem}"

    local sys_disk
    sys_disk=$(df -h "${INSTALL_DIR}" 2>/dev/null | awk 'NR==2 {print $3 " 已用 / " $2 " 总计 (" $5 " 使用率)"}' || echo "N/A")
    echo -e "  磁盘:  ${sys_disk}"

    local sys_uptime
    sys_uptime=$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/.*up /已运行 /' | sed 's/, *[0-9]* user.*//' || echo "N/A")
    echo -e "  运行:  ${sys_uptime}"

    local sys_load
    sys_load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo "N/A")
    echo -e "  负载:  ${sys_load}"

    echo ""
    echo -e "${CYAN}──────────────── 访问地址 (Access URLs) ────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}主站:${NC}        https://${DOMAIN}"
    echo -e "  ${GREEN}API:${NC}         https://${API_DOMAIN}"
    echo -e "  ${GREEN}CDN:${NC}         https://${CDN_DOMAIN}"
    echo -e "  ${GREEN}健康检查:${NC}    curl http://127.0.0.1:${BACKEND_PORT}/_internal/health"
    echo -e "  ${GREEN}镜像模式:${NC}    ${mirror_status}"

    echo ""
    echo -e "${CYAN}──────────────── 仪表盘/用户后台 ────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}仪表盘主页:${NC}    https://${DOMAIN}/dashboard"
    echo -e "  ${GREEN}通知中心:${NC}       https://${DOMAIN}/dashboard/notifications"
    echo -e "  ${GREEN}活跃举报:${NC}       https://${DOMAIN}/dashboard/reports"
    echo -e "  ${GREEN}统计分析:${NC}       https://${DOMAIN}/dashboard/analytics"
    echo -e "  ${GREEN}我的资源:${NC}       https://${DOMAIN}/dashboard/projects"
    echo -e "  ${GREEN}团队管理:${NC}       https://${DOMAIN}/dashboard/organizations"
    echo -e "  ${GREEN}收藏集:${NC}         https://${DOMAIN}/dashboard/collections"
    echo -e "  ${GREEN}购买记录:${NC}       https://${DOMAIN}/dashboard/purchases"
    echo ""
    echo -e "  ${YELLOW}登录后自动跳转至 /dashboard${NC}"

    echo ""
    echo -e "${CYAN}──────────────── Web 管理后台 (需管理员权限) ────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}管理后台首页:${NC}   https://${DOMAIN}/moderation"
    echo -e "  ${GREEN}审核资源:${NC}       https://${DOMAIN}/moderation/review"
    echo -e "  ${GREEN}举报管理:${NC}       https://${DOMAIN}/moderation/reports"
    echo -e "  ${GREEN}翻译审核:${NC}       https://${DOMAIN}/moderation/translations"
    echo -e "  ${GREEN}封禁申诉:${NC}       https://${DOMAIN}/moderation/appeals"
    echo -e "  ${GREEN}资料审核:${NC}       https://${DOMAIN}/moderation/profile-reviews"
    echo -e "  ${GREEN}图片审核:${NC}       https://${DOMAIN}/moderation/image-reviews"
    echo ""
    echo -e "  ${YELLOW}# 设置管理员账户${NC}"
    echo -e "  bash ${INSTALL_DIR}/deploy.sh set-admin"
    echo -e "  或手动: UPDATE users SET role='admin' WHERE username='你的用户名';"
    echo ""
    echo -e "  ${YELLOW}# 访问步骤${NC}"
    echo -e "  1. 注册/登录账户: https://${DOMAIN}/login"
    echo -e "  2. 提升为管理员: bash ${INSTALL_DIR}/deploy.sh set-admin"
    echo -e "  3. 访问管理后台: https://${DOMAIN}/moderation"

    echo ""
    echo -e "${CYAN}──────────────── 管理后台 API (Admin) ────────────────${NC}"
    echo ""
    echo -e "  ${GREEN}Admin Key:${NC}     ${ADMIN_KEY}"
    echo ""
    echo -e "  ${YELLOW}# 内部管理接口 (需 Modrinth-Admin 请求头认证)${NC}"
    echo -e "  POST   https://${API_DOMAIN}/_internal/admin/_force_reindex"
    echo -e "  POST   https://${API_DOMAIN}/_internal/admin/_fix_modpack_loaders"
    echo -e "  PATCH  https://${API_DOMAIN}/_internal/admin/_count-download"
    echo ""
    echo -e "  ${YELLOW}# v2 接口 (需 Modrinth-Admin 请求头认证)${NC}"
    echo -e "  POST   https://${API_DOMAIN}/v2/admin/_force_reindex"
    echo -e "  POST   https://${API_DOMAIN}/v2/admin/_fix_modpack_loaders"
    echo -e "  PATCH  https://${API_DOMAIN}/v2/admin/_count-download"
    echo ""
    echo -e "  使用方式: curl -H 'Modrinth-Admin: <ADMIN_KEY>' <METHOD> <URL>"
    echo -e "  例如: curl -X POST -H 'Modrinth-Admin: ${ADMIN_KEY}' https://${API_DOMAIN}/v2/admin/_force_reindex"

    echo ""
    echo -e "${CYAN}──────────────── 管理命令 (Management) ────────────────${NC}"
    echo ""
    echo -e "  ${YELLOW}# 服务状态/重启${NC}"
    echo -e "  systemctl status  bbsmc-labrinth bbsmc-frontend"
    echo -e "  systemctl restart bbsmc-labrinth bbsmc-frontend"
    echo -e "  systemctl stop    bbsmc-labrinth bbsmc-frontend"
    echo ""
    echo -e "  ${YELLOW}# 实时日志${NC}"
    echo -e "  journalctl -u bbsmc-labrinth -f"
    echo -e "  journalctl -u bbsmc-frontend -f"
    echo -e "  tail -f /var/log/bbsmc-labrinth.log"
    echo -e "  tail -f /var/log/bbsmc-frontend.log"
    echo ""
    echo -e "  ${YELLOW}# 数据库管理${NC}"
    echo -e "  cd ${INSTALL_DIR}"
    echo -e "  docker compose -f docker-compose.prod.yml ps"
    echo -e "  docker compose -f docker-compose.prod.yml logs -f postgres_db"
    echo -e "  docker compose -f docker-compose.prod.yml logs -f redis_cache"
    echo -e "  docker compose -f docker-compose.prod.yml logs -f meilisearch"
    echo -e "  docker compose -f docker-compose.prod.yml logs -f clickhouse"
    echo ""
    echo -e "  ${YELLOW}# Nginx 管理${NC}"
    echo -e "  nginx -t"
    echo -e "  nginx -s reload"
    echo -e "  systemctl status nginx"
    echo ""
    echo -e "  ${YELLOW}# 凭据文件${NC}"
    echo -e "  ${INSTALL_DIR}/deploy-credentials.txt  (chmod 600)"

    echo ""
    echo -e "${YELLOW}──────────────── 后续建议 ────────────────${NC}"
    echo ""
    echo -e "  1. 在宝塔面板 -> 网站 -> SSL, 确认证书已申请 (如自动申请失败)"
    echo -e "  2. 编辑 ${INSTALL_DIR}/apps/labrinth/.env 配置 OAuth/SMTP/支付等第三方服务"
    echo -e "  3. 配置定时备份: ${DATA_DIR} 目录"
    echo -e "  4. 在宝塔面板 -> 计划任务, 添加数据库定时备份"
    echo -e "  5. 修改宝塔面板默认端口与登录入口 (安全建议)"

    # 常见问题快速修复
    echo ""
    echo -e "${YELLOW}──────────────── 常见问题快速修复 ────────────────${NC}"
    echo ""
    echo -e "  ${RED}# 网站显示 404 Not Found?${NC}"
    echo -e "  1. 检查前端服务: systemctl status bbsmc-frontend"
    echo -e "  2. 重启前端: systemctl restart bbsmc-frontend"
    echo -e "  3. 测试本地: curl -I http://127.0.0.1:${FRONTEND_PORT}"
    echo -e "  4. 查看日志: tail -30 /var/log/bbsmc-frontend.log"
    echo ""
    echo -e "  ${RED}# 网站显示 502 Bad Gateway?${NC}"
    echo -e "  1. 前端/后端服务未启动, 检查 systemctl status"
    echo -e "  2. .env 配置错误, 检查 ${INSTALL_DIR}/apps/labrinth/.env"
    echo ""
    echo -e "  ${RED}# SSL 证书未配置/显示不安全?${NC}"
    echo -e "  方法 1: 宝塔面板 -> 网站 -> ${DOMAIN} -> SSL -> Let's Encrypt"
    echo -e "  方法 2: 已有证书但 Nginx 未应用? 执行以下命令:"
    echo -e "    bash ${INSTALL_DIR}/deploy.sh apply-ssl"
    echo -e "  方法 3: 手动应用证书到 Nginx (示例):"
    echo -e "    CERT=/www/server/panel/vhost/cert/${DOMAIN}/fullchain.pem"
    echo -e "    KEY=/www/server/panel/vhost/cert/${DOMAIN}/privkey.pem"
    echo -e "    CONF=/www/server/panel/vhost/nginx/${DOMAIN}.conf"
    echo -e "    sed -i '/listen 80;/a\\\n    listen 443 ssl;\\\n    ssl_certificate    '\$CERT';\\\n    ssl_certificate_key '\$KEY';\\\n    ssl_protocols TLSv1.2 TLSv1.3;' \$CONF"
    echo -e "    nginx -t && nginx -s reload"
    echo ""
    echo -e "  ${RED}# Nginx 配置不生效?${NC}"
    echo -e "  1. nginx -t (检查语法)"
    echo -e "  2. nginx -s reload (重新加载)"
    echo -e "  3. 检查是否有 0.default.conf 冲突: ls /www/server/panel/vhost/nginx/"
    echo ""
    echo -e "  ${RED}# 无法访问/登录管理后台?${NC}"
    echo -e "  1. 检查账户角色: bash ${INSTALL_DIR}/deploy.sh verify-admin"
    echo -e "  2. 设置管理员: bash ${INSTALL_DIR}/deploy.sh set-admin <用户名>"
    echo -e "  3. 检查后端服务: systemctl status bbsmc-labrinth"
    echo -e "  4. 前端登录页面: https://${DOMAIN}/login"
    echo -e "  5. 管理后台地址: https://${DOMAIN}/moderation"
    echo ""
    echo -e "  ${RED}# Admin API 返回认证错误?${NC}"
    echo -e "  正确的认证方式:"
    echo -e "  - 使用请求头: Modrinth-Admin: <ADMIN_KEY>"
    echo -e "  - 不要使用: Authorization: Bearer <ADMIN_KEY>"
    echo -e "  示例: curl -X POST -H 'Modrinth-Admin: <KEY>' https://${API_DOMAIN}/v2/admin/_force_reindex"
    echo -e "  查看 Admin Key: cat ${INSTALL_DIR}/deploy-credentials.txt | grep Admin"
    echo ""
    echo -e "  ${RED}# Docker 数据库服务异常?${NC}"
    echo -e "  一键重启所有 Docker 服务:"
    echo -e "  bash ${INSTALL_DIR}/deploy.sh restart-db"
    echo -e "  或手动:"
    echo -e "  cd ${INSTALL_DIR} && docker compose -f docker-compose.prod.yml down && docker compose -f docker-compose.prod.yml up -d"
    echo -e "  查看日志: docker logs --tail 100 <container_name>"

    # 镜像模式额外说明
    if [[ "${MIRROR_MODE}" == "1" ]]; then
        echo ""
        echo -e "${CYAN}──────────────── 镜像模式说明 ────────────────${NC}"
        echo ""
        echo -e "  - 浏览/搜索 GET:   代理到 modrinth.com / api.modrinth.com, 显示官方 mod"
        echo -e "  - 上传/修改 POST:  路由到本地 labrinth, 存储在本地数据库"
        echo -e "  - 本地 mod 访问:    先查本地, 404 时回源官网"
        echo -e "  - 用户/认证:        走本地 labrinth 本地用户体系"
        echo -e "  - 本地上传不同步到官网"
        echo -e "  - 禁用镜像: cp /www/server/panel/vhost/nginx/${DOMAIN}.conf.nomirror /www/server/panel/vhost/nginx/${DOMAIN}.conf"
        echo -e "              cp /www/server/panel/vhost/nginx/${API_DOMAIN}.conf.nomirror /www/server/panel/vhost/nginx/${API_DOMAIN}.conf"
        echo -e "              nginx -s reload"
    fi

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║   部署完成! enjoy your BBSMC instance!                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ---------------------- 卸载 ----------------------
uninstall() {
    echo -e "${CYAN}"
    echo "============================================================"
    echo "   BBSMC 卸载"
    echo "============================================================"
    echo -e "${NC}"

    if [[ "${FORCE_UNINSTALL}" != "1" ]]; then
        warn "此操作将删除所有 BBSMC 相关文件、数据库容器和 systemd 服务!"
        warn "数据目录 (${DATA_DIR}) 将被完全清除!"
        if [[ "${FULL_PURGE}" == "1" ]]; then
            warn "完整清理模式: 还将卸载 Rust/Node/Docker/宝塔!"
        fi
        read -rp "确认卸载? (输入 YES 确认): " confirm
        [[ "${confirm}" != "YES" ]] && { info "已取消卸载"; exit 0; }
    fi

    local INSTALL_DIR="${INSTALL_DIR:-/www/wwwroot/bbsmc}"
    local DATA_DIR="${DATA_DIR:-/www/wwwroot/bbsmc-data}"

    # 停止并禁用 systemd 服务
    info "停止 systemd 服务..."
    systemctl stop bbsmc-labrinth 2>/dev/null || true
    systemctl disable bbsmc-labrinth 2>/dev/null || true
    systemctl stop bbsmc-frontend 2>/dev/null || true
    systemctl disable bbsmc-frontend 2>/dev/null || true
    rm -f /etc/systemd/system/bbsmc-labrinth.service
    rm -f /etc/systemd/system/bbsmc-frontend.service
    systemctl daemon-reload

    # 停止并删除 Docker 容器
    info "清理 Docker 容器..."
    cd "${INSTALL_DIR}" 2>/dev/null || true
    if [[ -f "docker-compose.prod.yml" ]]; then
        docker compose -f docker-compose.prod.yml down -v 2>/dev/null || true
    fi
    docker rm -f bbsmc-postgres 2>/dev/null || true
    docker rm -f bbsmc-redis 2>/dev/null || true
    docker rm -f bbsmc-meilisearch 2>/dev/null || true
    docker rm -f bbsmc-clickhouse 2>/dev/null || true

    # 删除 Nginx 配置
    info "清理 Nginx 配置..."
    rm -f "/www/server/panel/vhost/nginx/${DOMAIN:-bbsmc.org.cn}.conf" 2>/dev/null || true
    rm -f "/www/server/panel/vhost/nginx/${DOMAIN:-bbsmc.org.cn}.conf.nomirror" 2>/dev/null || true
    rm -f "/www/server/panel/vhost/nginx/api.${DOMAIN:-bbsmc.org.cn}.conf" 2>/dev/null || true
    rm -f "/www/server/panel/vhost/nginx/api.${DOMAIN:-bbsmc.org.cn}.conf.nomirror" 2>/dev/null || true
    rm -f "/www/server/panel/vhost/nginx/cdn.${DOMAIN:-bbsmc.org.cn}.conf" 2>/dev/null || true
    rm -f "/www/server/panel/vhost/nginx/cdn.${DOMAIN:-bbsmc.org.cn}.conf.nomirror" 2>/dev/null || true
    nginx -s reload 2>/dev/null || true

    # 删除日志
    info "清理日志..."
    rm -f /var/log/bbsmc-labrinth.log 2>/dev/null || true
    rm -f /var/log/bbsmc-migration.log 2>/dev/null || true

    # 删除数据目录
    if [[ "${KEEP_DATA}" != "1" ]]; then
        info "删除数据目录 ${DATA_DIR}..."
        rm -rf "${DATA_DIR}"
    else
        info "保留数据目录 (KEEP_DATA=1)"
    fi

    # 删除安装目录
    info "删除安装目录 ${INSTALL_DIR}..."
    rm -rf "${INSTALL_DIR}"

    # 删除 cargo/rust 配置
    info "清理 Cargo/Rust 配置..."
    rm -f ~/.cargo/config.toml
    rm -rf ~/.cargo/registry/cache ~/.cargo/registry/index

    # ---------- 完整清理模式 ----------
    if [[ "${FULL_PURGE}" == "1" ]]; then
        warn "执行完整清理 (卸载 Rust/Node/Docker/宝塔)..."

        # 卸载 Rust
        if command -v rustup &>/dev/null; then
            info "卸载 Rust..."
            rustup self uninstall -y 2>/dev/null || true
            rm -rf ~/.cargo ~/.rustup
        fi

        # 卸载 Node.js
        if command -v node &>/dev/null; then
            info "卸载 Node.js..."
            # 通过 NodeSource 安装的
            apt-get purge -y nodejs 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            rm -f /etc/apt/sources.list.d/nodesource.list
            rm -f /etc/apt/keyrings/nodesource.gpg
            # 手动安装的
            rm -rf /usr/local/lib/nodejs 2>/dev/null || true
            rm -f /usr/local/bin/node /usr/local/bin/npx 2>/dev/null || true
            # pnpm
            if command -v pnpm &>/dev/null; then
                npm uninstall -g pnpm 2>/dev/null || true
                rm -f /usr/local/bin/pnpm /usr/local/bin/pnpx 2>/dev/null || true
            fi
        fi

        # 卸载 Docker
        if command -v docker &>/dev/null; then
            info "卸载 Docker..."
            apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
            rm -rf /etc/docker
            rm -rf /var/lib/docker
            rm -rf /var/lib/containerd
        fi

        # 卸载宝塔面板
        if [[ -f /www/server/panel/install/uninstall.sh ]]; then
            info "卸载宝塔面板..."
            cd /www/server/panel/install && bash uninstall.sh 2>/dev/null || true
        elif [[ -f /etc/init.d/bt ]]; then
            info "卸载宝塔面板 (备用方式)..."
            /etc/init.d/bt stop 2>/dev/null || true
            rm -f /etc/init.d/bt
            update-rc.d -f bt remove 2>/dev/null || true
        fi

        # 清理 Swap
        info "清理 Swap..."
        if [[ -f /swapfile ]]; then
            swapoff /swapfile 2>/dev/null || true
            rm -f /swapfile
            # 从 fstab 移除
            sed -i '/\/swapfile/d' /etc/fstab 2>/dev/null || true
        fi

        # 清理 apt 缓存
        info "清理 apt 缓存..."
        apt-get clean
        apt-get autoremove -y
    fi

    info "卸载完成!"
    if [[ "${FULL_PURGE}" == "1" ]]; then
        info "完整清理已完成, 系统已恢复到部署前状态"
    else
        info "如需重新部署, 运行: ./deploy.sh"
    fi
}

# ---------------------- 从已有配置恢复域名变量 ----------------------
recover_domain_vars() {
    # 如果 DOMAIN 已设置, 跳过
    if [[ -n "${DOMAIN}" ]] && [[ -n "${API_DOMAIN}" ]] && [[ -n "${CDN_DOMAIN}" ]]; then
        return 0
    fi

    # 优先级: 环境变量 > .env 文件 > nginx 配置 > 交互输入
    local env_file="${INSTALL_DIR}/bin/.env"
    [[ ! -f "${env_file}" ]] && env_file="${INSTALL_DIR}/apps/labrinth/.env"

    # 从 .env 恢复域名
    if [[ -f "${env_file}" ]]; then
        local site_url self_addr cdn_url
        site_url=$(grep '^SITE_URL=' "${env_file}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/https\?:\/\///' | sed 's/\/.*//')
        self_addr=$(grep '^SELF_ADDR=' "${env_file}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/https\?:\/\///' | sed 's/\/.*//')
        cdn_url=$(grep '^CDN_URL=' "${env_file}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/https\?:\/\///' | sed 's/\/.*//')

        [[ -n "${site_url}" ]] && DOMAIN="${site_url}"
        [[ -n "${self_addr}" ]] && API_DOMAIN="${self_addr}"
        [[ -n "${cdn_url}" ]] && CDN_DOMAIN="${cdn_url}"
    fi

    # 如果仍缺失, 从已有 nginx 配置恢复
    local vhost_dir="/www/server/panel/vhost/nginx"
    if [[ -d "${vhost_dir}" ]]; then
        for conf in "${vhost_dir}"/*.conf; do
            [[ -f "${conf}" ]] || continue
            local sn
            sn=$(grep -m1 'server_name' "${conf}" 2>/dev/null | grep -oP 'server_name\s+\K\S+' || true)
            [[ -z "${sn}" ]] && continue

            if [[ -z "${DOMAIN}" ]] && [[ "${sn}" != api.* ]] && [[ "${sn}" != cdn.* ]] && [[ "${sn}" != *.conf ]]; then
                # 可能是主站域名
                DOMAIN="${sn}"
            elif [[ -z "${API_DOMAIN}" ]] && [[ "${sn}" == api.* ]]; then
                API_DOMAIN="${sn}"
            elif [[ -z "${CDN_DOMAIN}" ]] && [[ "${sn}" == cdn.* ]]; then
                CDN_DOMAIN="${sn}"
            fi
        done
    fi

    # 最后兜底: 从 DOMAIN 推导
    if [[ -n "${DOMAIN}" ]]; then
        [[ -z "${API_DOMAIN}" ]] && API_DOMAIN="api.${DOMAIN}"
        [[ -z "${CDN_DOMAIN}" ]] && CDN_DOMAIN="cdn.${DOMAIN}"
    fi

    # 如果 DOMAIN 仍为空, 交互询问
    if [[ -z "${DOMAIN}" ]]; then
        read -rp "请输入主域名 (例如: bbsmc.org.cn): " DOMAIN
        [[ -z "${DOMAIN}" ]] && error "域名不能为空"
        DOMAIN="${DOMAIN#https://}"
        DOMAIN="${DOMAIN#http://}"
        DOMAIN="${DOMAIN%%/*}"
        [[ -z "${API_DOMAIN}" ]] && API_DOMAIN="api.${DOMAIN}"
        [[ -z "${CDN_DOMAIN}" ]] && CDN_DOMAIN="cdn.${DOMAIN}"
    fi

    info "域名配置: ${DOMAIN} | API: ${API_DOMAIN} | CDN: ${CDN_DOMAIN}"
}

# ---------------------- 修复 Nginx 配置 ----------------------
fix_nginx_configs() {
    step "修复 Nginx 配置"

    # 恢复域名变量
    recover_domain_vars

    local NGINX_CONF_DIR="/www/server/panel/vhost/nginx"
    local NGINX_MAIN=""
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")

    # 检测镜像模式: 在写入非镜像配置之前, 先检查现有配置
    local mirror_mode_active=0
    if [[ -f "${NGINX_CONF_DIR}/${API_DOMAIN}.conf" ]]; then
        if grep -q "api.modrinth.com" "${NGINX_CONF_DIR}/${API_DOMAIN}.conf" 2>/dev/null; then
            mirror_mode_active=1
            info "检测到现有镜像模式配置, 将在修复后重新应用"
        fi
    fi
    # 也检查 MIRROR_MODE 环境变量
    if [[ "${MIRROR_MODE}" == "1" ]]; then
        mirror_mode_active=1
        info "MIRROR_MODE=1 已设置, 将在修复后应用镜像模式配置"
    fi

    # 自动检测宝塔 nginx 配置路径 (用 nginx -V 获取真实 conf-path)
    local nginx_real_conf
    nginx_real_conf=$("${nginx_bin}" -V 2>&1 | grep -oP '\-\-conf-path=\K[^ ]+' 2>/dev/null)
    if [[ -n "${nginx_real_conf}" && -f "${nginx_real_conf}" ]]; then
        NGINX_MAIN="${nginx_real_conf}"
    elif [[ -f "/etc/nginx/nginx.conf" ]]; then
        NGINX_MAIN="/etc/nginx/nginx.conf"
    elif [[ -f "/www/server/nginx/conf/nginx.conf" ]]; then
        NGINX_MAIN="/www/server/nginx/conf/nginx.conf"
    else
        NGINX_MAIN="/etc/nginx/nginx.conf"
    fi
    info "nginx.conf 路径: ${NGINX_MAIN}"

    # 如果 nginx.conf 缺少 events 块, 自动修复
    if [[ -f "${NGINX_MAIN}" ]] && ! grep -q "events[[:space:]]*{" "${NGINX_MAIN}" 2>/dev/null; then
        warn "${NGINX_MAIN} 缺少 events 块, 尝试修复"
        [[ -f "${NGINX_MAIN}" ]] && /bin/cp -f "${NGINX_MAIN}" "${NGINX_MAIN}.bak.$(date +%s)" 2>/dev/null || true
        if [[ -f "/www/server/nginx/conf/nginx.conf" ]] && grep -q "events[[:space:]]*{" "/www/server/nginx/conf/nginx.conf" 2>/dev/null && [[ "${NGINX_MAIN}" != "/www/server/nginx/conf/nginx.conf" ]]; then
            warn "从 /www/server/nginx/conf/nginx.conf 恢复"
            /bin/cp -f "/www/server/nginx/conf/nginx.conf" "${NGINX_MAIN}" 2>/dev/null || true
        else
            warn "创建最小 nginx.conf (已备份原文件)"
            local mime_path="/etc/nginx/mime.types"
            [[ -f "${mime_path}" ]] || mime_path="/www/server/nginx/conf/mime.types"
            [[ -f "${mime_path}" ]] || mime_path="/www/server/nginx/conf/nginx_mime_types.conf"
            [[ -f "${mime_path}" ]] || mime_path=""
            local mime_include=""
            [[ -n "${mime_path}" ]] && mime_include="include ${mime_path};"
            cat > "${NGINX_MAIN}" << NGINXDEFAULT
user www-data;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    ${mime_include}
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    include /etc/nginx/conf.d/*.conf;
    include /www/server/panel/vhost/nginx/*.conf;
}
NGINXDEFAULT
        fi
    fi

    local nginx_conf_base
    nginx_conf_base=$(/usr/bin/dirname "${NGINX_MAIN}")
    local conf_d="${nginx_conf_base}/conf.d"

    # 0. 无条件创建必要目录
    /bin/mkdir -p "${conf_d}" 2>/dev/null || true
    /bin/mkdir -p "${NGINX_CONF_DIR}" 2>/dev/null || true
    /bin/mkdir -p "${DATA_DIR}/uploads" 2>/dev/null || true

    # 0.1 modrinth.conf 兜底修复 (宝塔常见问题: 损坏的符号链接)
    if [[ -f "${NGINX_MAIN}" ]] && grep -q "modrinth.conf" "${NGINX_MAIN}" 2>/dev/null; then
        local modrinth_conf="${conf_d}/modrinth.conf"
        if [[ -L "${modrinth_conf}" ]] && [[ ! -e "${modrinth_conf}" ]]; then
            warn "modrinth.conf 是损坏的符号链接, 自动删除"
            /bin/rm -f "${modrinth_conf}" 2>/dev/null || true
        fi
        if [[ ! -f "${modrinth_conf}" ]]; then
            printf "# Auto-generated placeholder for modrinth include\n" > "${modrinth_conf}" 2>/dev/null || true
            info "  修复 modrinth.conf 缺失"
        fi
    fi

    # 0.2 conf.d 占位文件 (防止通配符 include 空目录报错)
    if ! ls "${conf_d}"/*.conf >/dev/null 2>&1; then
        printf "# Auto-generated placeholder\n" > "${conf_d}/placeholder.conf" 2>/dev/null || true
    fi

    # 1. 修复 nginx.conf 中的 include
    if [[ -f "${NGINX_MAIN}" ]]; then
        local tmpfile
        tmpfile=$(/bin/mktemp)
        sed -n 's/^[[:space:]]*include[[:space:]]\+\([^;]*\)[[:space:]]*;[[:space:]]*$/\1/p' "${NGINX_MAIN}" 2>/dev/null \
            | tr -d '\r' \
            > "${tmpfile}"

        while IFS= read -r inc; do
            inc="${inc//[$' \t\r']/}"
            [[ -z "${inc}" ]] && continue
            for f in ${inc}; do
                [[ -z "${f}" ]] && continue
                f="${f//\"/}"
                f="${f//\'/}"

                local dir
                dir=$(/usr/bin/dirname "${f}")
                /bin/mkdir -p "${dir}" 2>/dev/null || true

                if [[ "${f}" == *"*"* ]] || [[ "${f}" == *"?"* ]]; then
                    local count
                    count=$(ls "${dir}"/*.conf 2>/dev/null | wc -l)
                    if [[ ${count} -eq 0 ]]; then
                        printf "# Auto-generated placeholder for nginx wildcard include\n" > "${dir}/placeholder.conf" 2>/dev/null || true
                        info "  创建通配符占位: ${dir}/placeholder.conf"
                    fi
                else
                    # 先处理损坏的符号链接
                    if [[ -L "${f}" ]] && [[ ! -e "${f}" ]]; then
                        warn "  发现损坏的符号链接: ${f}"
                        /bin/rm -f "${f}" 2>/dev/null || true
                    fi
                    if [[ ! -e "${f}" ]]; then
                        printf "# Auto-generated placeholder for nginx include\n" > "${f}" 2>/dev/null || {
                            /bin/mkdir -p "$(/usr/bin/dirname "${f}")" 2>/dev/null || true
                            printf "# Auto-generated placeholder\n" > "${f}" 2>/dev/null || true
                        }
                        info "  创建占位: ${f}"
                    fi
                fi
            done
        done < "${tmpfile}"
        /bin/rm -f "${tmpfile}"

        # 确保宝塔 vhost 被 include
        if ! grep -q "vhost/nginx" "${NGINX_MAIN}" 2>/dev/null; then
            warn "nginx.conf 未 include 宝塔 vhost 目录, 自动添加"
            sed -i '/http {/a\    include /www/server/panel/vhost/nginx/*.conf;' "${NGINX_MAIN}"
        fi
    fi

    # 1.1 禁用宝塔默认 0.default.conf (它会拦截所有未匹配的请求)
    local default_conf="${NGINX_CONF_DIR}/0.default.conf"
    if [[ -f "${default_conf}" ]]; then
        warn "检测到 ${default_conf}, 重命名为 .disabled 避免拦截请求"
        /bin/mv -f "${default_conf}" "${default_conf}.disabled" 2>/dev/null || true
    fi

    # 1.1.5 清理问题配置文件 (phpfpm_status.conf 等)
    fix_quic_and_corrupted "${NGINX_CONF_DIR}"
    cleanup_problematic_configs "${NGINX_CONF_DIR}"
    disable_unknown_domain_configs "${NGINX_CONF_DIR}" "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"

    # 1.2 写入默认 catch-all server (兜底, 防止默认 404 页)
    info "写入默认 catch-all server"
    cat > "${NGINX_CONF_DIR}/_catch_all.conf" <<EOFCONF
server {
    listen 80 default_server;
    server_name _;
    return 301 https://${DOMAIN}\$request_uri;
}
EOFCONF

    # 2. 写入主站配置
    info "写入主站配置: ${DOMAIN} -> ${FRONTEND_PORT}"
    cat > "${NGINX_CONF_DIR}/${DOMAIN}.conf" <<EOFCONF
server {
    listen 80;
    server_name ${DOMAIN};
    index index.html;
    client_max_body_size 1024m;

    location / {
        proxy_pass http://127.0.0.1:${FRONTEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_buffering off;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|webp)\$ {
        proxy_pass http://127.0.0.1:${FRONTEND_PORT};
        expires 7d;
        add_header Cache-Control "public, immutable";
    }

    location ~ /\. {
        deny all;
    }
}
EOFCONF

    # 3. 写入 API 配置
    info "写入 API 配置: ${API_DOMAIN} -> ${BACKEND_PORT}"
    cat > "${NGINX_CONF_DIR}/${API_DOMAIN}.conf" <<EOFCONF
server {
    listen 80;
    server_name ${API_DOMAIN};
    client_max_body_size 1024m;

    location / {
        proxy_pass http://127.0.0.1:${BACKEND_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
        proxy_buffering off;
    }
}
EOFCONF

    # 4. 写入 CDN 配置
    info "写入 CDN 配置: ${CDN_DOMAIN} -> 静态文件"
    cat > "${NGINX_CONF_DIR}/${CDN_DOMAIN}.conf" <<EOFCONF
server {
    listen 80;
    server_name ${CDN_DOMAIN};
    root ${DATA_DIR}/uploads;
    client_max_body_size 1024m;

    location / {
        try_files \$uri \$uri/ =404;
        add_header Access-Control-Allow-Origin *;
        add_header Access-Control-Allow-Methods 'GET, OPTIONS';
    }

    location ~* \.(jpg|jpeg|png|gif|webp|svg|ico|css|js|woff|woff2)\$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    location ~ /\. {
        deny all;
    }
}
EOFCONF

    # 5. 测试并启动 Nginx
    info "测试 Nginx 配置..."
    fix_quic_and_corrupted "${NGINX_CONF_DIR}"
    fix_nginx_http2_compat "${NGINX_CONF_DIR}"
    cleanup_problematic_configs "${NGINX_CONF_DIR}"
    cleanup_duplicate_mime "${NGINX_CONF_DIR}"
    local test_output
    test_output=$("${nginx_bin}" -t 2>&1) || true
    echo "${test_output}"

    if echo "${test_output}" | grep -q "successful"; then
        if pgrep -x nginx > /dev/null 2>&1; then
            "${nginx_bin}" -s reload 2>/dev/null || "${nginx_bin}" 2>/dev/null || true
            info "Nginx 已 reload ✓"
        else
            "${nginx_bin}" 2>/dev/null || systemctl start nginx 2>/dev/null || true
            info "Nginx 已 start ✓"
        fi
    else
        warn "配置测试失败, 执行强制修复..."
        fix_nginx_force_recovery "${NGINX_CONF_DIR}"
    fi

    # 6. 验证
    sleep 1
    if pgrep -x nginx > /dev/null 2>&1; then
        info "Nginx 运行中 ✓"
    else
        warn "Nginx 未运行, 请手动: nginx -t"
    fi

    # 7. 测试反代
    info "验证反代..."
    for domain in "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"; do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 \
            -H "Host: ${domain}" http://127.0.0.1 2>/dev/null || echo "000")
        if [[ "${code}" != "000" ]]; then
            info "  ${domain}: HTTP ${code} ✓"
        else
            warn "  ${domain}: HTTP ${code} ✗"
        fi
    done

    # 8. 应用 SSL 证书 (如果已有)
    info "检测并应用 SSL 证书..."
    setup_ssl

    # 9. 检测并应用镜像模式配置 (如果之前启用了镜像模式)
    if [[ "${mirror_mode_active}" == "1" ]]; then
        info "应用镜像模式 Nginx 配置 (error_page+return 模式, 避免 builder error)..."
        # 从现有配置检测到的镜像模式, 强制设置 MIRROR_MODE
        MIRROR_MODE=1
        setup_modrinth_mirror
    fi
}

# ---------------------- 重新配置第三方服务 ----------------------
reconfigure_third_party() {
    step "重新配置第三方服务"

    local env_file="${INSTALL_DIR}/apps/labrinth/.env"
    [[ ! -f "${env_file}" ]] && env_file="${INSTALL_DIR}/bin/.env"
    [[ ! -f "${env_file}" ]] && error "未找到 .env 文件, 请先部署"

    echo -e "${CYAN}当前 .env 文件: ${env_file}${NC}"
    echo ""

    # 读取当前配置状态
    local curr_github_id curr_github_sec curr_ms_id curr_ms_sec
    curr_github_id=$(grep "^GITHUB_CLIENT_ID=" "${env_file}" 2>/dev/null | cut -d= -f2)
    curr_github_sec=$(grep "^GITHUB_CLIENT_SECRET=" "${env_file}" 2>/dev/null | cut -d= -f2)
    curr_ms_id=$(grep "^MICROSOFT_CLIENT_ID=" "${env_file}" 2>/dev/null | cut -d= -f2)
    curr_ms_sec=$(grep "^MICROSOFT_CLIENT_SECRET=" "${env_file}" 2>/dev/null | cut -d= -f2)

    echo -e "${CYAN}当前配置状态:${NC}"
    echo "  GitHub:     ${curr_github_id:-none}"
    echo "  Microsoft:  ${curr_ms_id:-none}"
    echo ""

    # 交互式输入新配置
    echo -e "${CYAN}=== OAuth 登录配置 ===${NC}"
    echo "  留空保持当前值不变"
    echo ""

    local callback_base
    callback_base="https://$(grep "^SELF_ADDR=" "${env_file}" 2>/dev/null | cut -d= -f2 | sed 's|/$||')/auth/callback"

    # GitHub
    echo -e "${YELLOW}--- GitHub 登录 ---${NC}"
    echo "  回调 URL: ${callback_base}/github"
    read -rp "  GitHub Client ID [当前: ${curr_github_id:-none}]: " INPUT
    [[ -n "${INPUT}" ]] && curr_github_id="${INPUT}"
    read -rp "  GitHub Client Secret [当前: ${curr_github_sec:-****}]: " INPUT
    [[ -n "${INPUT}" ]] && curr_github_sec="${INPUT}"

    # Microsoft
    local new_ms_id new_ms_sec
    echo ""
    echo -e "${YELLOW}--- Microsoft 登录 ---${NC}"
    echo "  回调 URL: ${callback_base}/microsoft"
    read -rp "  Microsoft Client ID [当前: ${curr_ms_id:-none}]: " INPUT
    [[ -n "${INPUT}" ]] && curr_ms_id="${INPUT}"
    read -rp "  Microsoft Client Secret [当前: ${curr_ms_sec:-****}]: " INPUT
    [[ -n "${INPUT}" ]] && curr_ms_sec="${INPUT}"

    # SMTP
    local curr_smtp_host curr_smtp_user curr_smtp_pass
    curr_smtp_host=$(grep "^SMTP_HOST=" "${env_file}" 2>/dev/null | cut -d= -f2)
    curr_smtp_user=$(grep "^SMTP_USERNAME=" "${env_file}" 2>/dev/null | cut -d= -f2)
    curr_smtp_pass=$(grep "^SMTP_PASSWORD=" "${env_file}" 2>/dev/null | cut -d= -f2)

    echo ""
    echo -e "${CYAN}=== SMTP 邮件配置 ===${NC}"
    echo "  当前: ${curr_smtp_host:-none} (${curr_smtp_user:-none})"
    read -rp "  SMTP 主机 [当前: ${curr_smtp_host:-none}]: " INPUT
    [[ -n "${INPUT}" ]] && curr_smtp_host="${INPUT}"
    if [[ -n "${curr_smtp_host}" ]] && [[ "${curr_smtp_host}" != "none" ]]; then
        read -rp "  SMTP 用户名 [当前: ${curr_smtp_user:-none}]: " INPUT
        [[ -n "${INPUT}" ]] && curr_smtp_user="${INPUT}"
        read -rp "  SMTP 密码 [当前: ****]: " INPUT
        [[ -n "${INPUT}" ]] && curr_smtp_pass="${INPUT}"
    fi

    # 写入 .env 文件
    echo ""
    info "写入 .env 配置..."

    # 备份原文件
    cp "${env_file}" "${env_file}.bak.$(date +%Y%m%d%H%M%S)"

    update_env_key "${env_file}" "GITHUB_CLIENT_ID" "${curr_github_id:-none}"
    update_env_key "${env_file}" "GITHUB_CLIENT_SECRET" "${curr_github_sec:-none}"
    update_env_key "${env_file}" "MICROSOFT_CLIENT_ID" "${curr_ms_id:-none}"
    update_env_key "${env_file}" "MICROSOFT_CLIENT_SECRET" "${curr_ms_sec:-none}"
    update_env_key "${env_file}" "SMTP_HOST" "${curr_smtp_host:-none}"
    update_env_key "${env_file}" "SMTP_USERNAME" "${curr_smtp_user:-none}"
    update_env_key "${env_file}" "SMTP_PASSWORD" "${curr_smtp_pass:-none}"

    # 同步到 bin/.env (如果存在)
    local bin_env="${INSTALL_DIR}/bin/.env"
    if [[ -f "${bin_env}" ]] && [[ "${bin_env}" != "${env_file}" ]]; then
        cp "${env_file}" "${bin_env}"
        info "  已同步到 bin/.env"
    fi

    # 重启服务使配置生效
    echo ""
    read -rp "是否重启后端服务使配置生效? [Y/n]: " RESTART
    if [[ "${RESTART}" =~ ^[Yy]$ ]] || [[ -z "${RESTART}" ]]; then
        if systemctl is-active bbsmc-labrinth &>/dev/null; then
            systemctl restart bbsmc-labrinth
            info "后端服务已重启"
        fi
    fi

    echo ""
    info "第三方服务配置完成!"
    info "可随时运行 '$0 reconfigure' 重新配置"
}

# ---------------------- 管理员账户管理 ----------------------
setup_admin_user() {
    step "设置管理员账户"

    local INSTALL_DIR="${INSTALL_DIR:-/www/wwwroot/bbsmc}"
    local ENV_FILE="${INSTALL_DIR}/apps/labrinth/.env"
    [[ ! -f "${ENV_FILE}" ]] && ENV_FILE="${INSTALL_DIR}/bin/.env"

    # 加载环境变量
    local DOMAIN="${DOMAIN:-bbsmc.org.cn}"
    if [[ -f "${ENV_FILE}" ]]; then
        DOMAIN=$(grep "^DOMAIN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        DOMAIN="${DOMAIN:-bbsmc.org.cn}"
    fi

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  BBSMC 管理员账户设置${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""

    # 检查后端服务是否运行
    if ! systemctl is-active bbsmc-labrinth &>/dev/null; then
        echo -e "${RED}错误: bbsmc-labrinth 服务未运行${NC}"
        echo -e "请先启动后端服务: systemctl start bbsmc-labrinth"
        return 1
    fi

    # 检查数据库连接
    local backend_code
    backend_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${BACKEND_PORT:-8000}/v2/tag/category" 2>/dev/null || echo "000")
    if [[ "${backend_code}" == "000" ]] || [[ "${backend_code}" == "502" ]]; then
        echo -e "${RED}错误: 后端 API 不可达 (HTTP ${backend_code})${NC}"
        echo -e "请检查: systemctl status bbsmc-labrinth"
        return 1
    fi

    # 交互式输入用户名
    local username
    if [[ -n "$1" ]]; then
        username="$1"
    else
        read -rp "输入要设为管理员的用户名: " username
    fi

    if [[ -z "${username}" ]]; then
        echo -e "${RED}错误: 用户名不能为空${NC}"
        return 1
    fi

    # 连接数据库更新角色
    if [[ -f "${ENV_FILE}" ]]; then
        local pg_pass pg_host pg_user pg_db
        pg_pass=$(grep "^PG_PASS=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        pg_host=$(grep "^PG_HOST=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "' | cut -d: -f1)
        pg_user=$(grep "^PG_USER=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        pg_db=$(grep "^PG_DB=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        pg_host="${pg_host:-127.0.0.1}"
        pg_user="${pg_user:-labrinth}"
        pg_db="${pg_db:-labrinth}"

        if command -v psql &>/dev/null; then
            echo ""
            echo -e "${YELLOW}正在查询用户信息...${NC}"

            local user_info
            user_info=$(PGPASSWORD="${pg_pass}" psql -h "${pg_host}" -U "${pg_user}" -d "${pg_db}" \
                -t -A -c "SELECT id, username, role FROM users WHERE username = '${username}';" 2>/dev/null)

            if [[ -z "${user_info}" ]]; then
                echo -e "${RED}错误: 用户 '${username}' 不存在${NC}"
                echo -e "请先在前端注册账户: https://${DOMAIN}/register"
                return 1
            fi

            local user_id user_name current_role
            user_id=$(echo "${user_info}" | cut -d'|' -f1)
            user_name=$(echo "${user_info}" | cut -d'|' -f2)
            current_role=$(echo "${user_info}" | cut -d'|' -f3)

            echo -e "  用户 ID: ${user_id}"
            echo -e "  用户名: ${user_name}"
            echo -e "  当前角色: ${current_role}"

            if [[ "${current_role}" == "admin" ]]; then
                echo ""
                echo -e "${GREEN}该用户已经是管理员!${NC}"
                echo ""
                echo -e "${YELLOW}管理后台地址:${NC} https://${DOMAIN}/moderation"
                return 0
            fi

            echo ""
            if [[ -n "$2" ]] && [[ "$2" == "--confirm" ]]; then
                echo "自动确认模式"
            else
                read -rp "确认将 '${username}' 设为管理员? [y/N]: " confirm
                if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
                    echo "已取消"
                    return 0
                fi
            fi

            echo ""
            echo -e "${YELLOW}正在更新用户角色...${NC}"

            PGPASSWORD="${pg_pass}" psql -h "${pg_host}" -U "${pg_user}" -d "${pg_db}" \
                -c "UPDATE users SET role = 'admin' WHERE username = '${username}';" 2>/dev/null

            if [[ $? -eq 0 ]]; then
                echo ""
                echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}  ✓ 管理员账户设置成功!${NC}"
                echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
                echo ""
                echo -e "${CYAN}访问步骤:${NC}"
                echo -e "  1. 登录账户: https://${DOMAIN}/login"
                echo -e "  2. 访问管理后台: https://${DOMAIN}/moderation"
                echo ""
                echo -e "${CYAN}可用管理功能:${NC}"
                echo -e "  ✓ 审核资源 (moderation/review)"
                echo -e "  ✓ 举报管理 (moderation/reports)"
                echo -e "  ✓ 封禁申诉 (moderation/appeals)"
                echo -e "  ✓ 翻译审核 (moderation/translations)"
                echo -e "  ✓ 资料审核 (moderation/profile-reviews)"
                echo -e "  ✓ 图片审核 (moderation/image-reviews)"
                echo -e "  ✓ 高级创作者 (moderation/creators)"
            else
                echo -e "${RED}错误: 更新失败${NC}"
                echo -e "请手动执行:"
                echo -e "  PGPASSWORD='${pg_pass}' psql -h ${pg_host} -U ${pg_user} -d ${pg_db}"
                echo -e "  UPDATE users SET role = 'admin' WHERE username = '${username}';"
                return 1
            fi
        else
            echo -e "${YELLOW}psql 未安装, 请手动设置管理员:${NC}"
            echo ""
            echo "  1. 安装 psql 客户端:"
            echo "     apt-get install -y postgresql-client"
            echo ""
            echo "  2. 或使用 Docker 容器:"
            echo "     docker exec -it postgres_db psql -U ${pg_user} -d ${pg_db}"
            echo "     UPDATE users SET role = 'admin' WHERE username = '${username}';"
            echo ""
            echo "  3. 获取 .env 中的密码:"
            echo "     grep PG_PASS ${ENV_FILE}"
            return 1
        fi
    else
        echo -e "${RED}错误: 未找到 .env 文件${NC}"
        echo -e "请先运行部署: bash ${0} install"
        return 1
    fi
}

verify_admin_access() {
    step "验证后台访问"

    local INSTALL_DIR="${INSTALL_DIR:-/www/wwwroot/bbsmc}"
    local ENV_FILE="${INSTALL_DIR}/apps/labrinth/.env"
    [[ ! -f "${ENV_FILE}" ]] && ENV_FILE="${INSTALL_DIR}/bin/.env"

    local DOMAIN="${DOMAIN:-bbsmc.org.cn}"
    local API_DOMAIN="${API_DOMAIN:-api.${DOMAIN}}"
    local FRONTEND_PORT="${FRONTEND_PORT:-3000}"
    local BACKEND_PORT="${BACKEND_PORT:-8000}"

    if [[ -f "${ENV_FILE}" ]]; then
        DOMAIN=$(grep "^DOMAIN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        API_SUBDOMAIN=$(grep "^API_SUBDOMAIN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        DOMAIN="${DOMAIN:-bbsmc.org.cn}"
        API_DOMAIN="${API_DOMAIN:-${API_SUBDOMAIN:-api}.${DOMAIN}}"
        FRONTEND_PORT=$(grep "^FRONTEND_PORT=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "' )
        BACKEND_PORT=$(grep "^BACKEND_PORT=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "' )
        FRONTEND_PORT="${FRONTEND_PORT:-3000}"
        BACKEND_PORT="${BACKEND_PORT:-8000}"
    fi

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  BBSMC 后台访问验证${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""

    local all_ok=1

    # 1. 后端服务状态
    echo -e "${YELLOW}[1] 后端服务 (bbsmc-labrinth)${NC}"
    local backend_state
    backend_state=$(systemctl is-active bbsmc-labrinth 2>/dev/null || echo "inactive")
    if [[ "${backend_state}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} 运行中"
    else
        echo -e "  ${RED}✗${NC} 未运行 (${backend_state})"
        echo -e "    执行: systemctl start bbsmc-labrinth"
        all_ok=0
    fi

    # 2. 前端服务状态
    echo -e "${YELLOW}[2] 前端服务 (bbsmc-frontend)${NC}"
    local frontend_state
    frontend_state=$(systemctl is-active bbsmc-frontend 2>/dev/null || echo "inactive")
    if [[ "${frontend_state}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} 运行中"
    else
        echo -e "  ${RED}✗${NC} 未运行 (${frontend_state})"
        echo -e "    执行: systemctl start bbsmc-frontend"
        all_ok=0
    fi

    # 3. Nginx 状态
    echo -e "${YELLOW}[3] Nginx 服务${NC}"
    local nginx_state
    nginx_state=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
    if [[ "${nginx_state}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} 运行中"
    else
        echo -e "  ${RED}✗${NC} 未运行 (${nginx_state})"
        echo -e "    执行: systemctl start nginx"
        all_ok=0
    fi

    # 4. 后端 API 可访问性
    echo -e "${YELLOW}[4] 后端 API 检查${NC}"
    local backend_code
    backend_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${BACKEND_PORT}/v2/tag/category" 2>/dev/null || echo "000")
    if [[ "${backend_code}" == "200" ]] || [[ "${backend_code}" == "401" ]] || [[ "${backend_code}" == "403" ]]; then
        echo -e "  ${GREEN}✓${NC} 本地 API 可达 (HTTP ${backend_code})"
    else
        echo -e "  ${RED}✗${NC} 本地 API 不可达 (HTTP ${backend_code})"
        all_ok=0
    fi

    # 5. 前端可访问性
    echo -e "${YELLOW}[5] 前端服务检查${NC}"
    local frontend_code
    frontend_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 3 --max-time 5 "http://127.0.0.1:${FRONTEND_PORT}" 2>/dev/null || echo "000")
    if [[ "${frontend_code}" == "200" ]] || [[ "${frontend_code}" == "301" ]] || [[ "${frontend_code}" == "302" ]]; then
        echo -e "  ${GREEN}✓${NC} 本地前端可达 (HTTP ${frontend_code})"
    else
        echo -e "  ${RED}✗${NC} 本地前端不可达 (HTTP ${frontend_code})"
        all_ok=0
    fi

    # 6. Nginx 反代配置检查
    echo -e "${YELLOW}[6] Nginx 反代配置${NC}"
    local nginx_conf="/www/server/panel/vhost/nginx/${DOMAIN}.conf"
    if [[ -f "${nginx_conf}" ]]; then
        echo -e "  ${GREEN}✓${NC} 主站配置存在"
    else
        echo -e "  ${RED}✗${NC} 主站配置不存在"
        all_ok=0
    fi

    local api_conf="/www/server/panel/vhost/nginx/${API_DOMAIN}.conf"
    if [[ -f "${api_conf}" ]]; then
        echo -e "  ${GREEN}✓${NC} API 配置存在"
    else
        echo -e "  ${RED}✗${NC} API 配置不存在"
        all_ok=0
    fi

    # 7. Admin API 认证验证
    echo -e "${YELLOW}[7] Admin API 认证检查${NC}"
    local admin_key=""
    if [[ -f "${INSTALL_DIR}/bin/.env" ]]; then
        admin_key=$(grep "^LABRINTH_ADMIN_KEY=" "${INSTALL_DIR}/bin/.env" 2>/dev/null | cut -d= -f2 | tr -d ' "')
    fi
    if [[ -z "${admin_key}" ]] && [[ -f "${INSTALL_DIR}/apps/labrinth/.env" ]]; then
        admin_key=$(grep "^LABRINTH_ADMIN_KEY=" "${INSTALL_DIR}/apps/labrinth/.env" 2>/dev/null | cut -d= -f2 | tr -d ' "')
    fi

    if [[ -n "${admin_key}" ]]; then
        local admin_test_code
        admin_test_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 3 --max-time 5 \
            -X POST \
            -H "Modrinth-Admin: ${admin_key}" \
            -H "Content-Type: application/json" \
            "http://127.0.0.1:${BACKEND_PORT}/_internal/admin/_force_reindex" 2>/dev/null || echo "000")
        if [[ "${admin_test_code}" == "200" ]] || [[ "${admin_test_code}" == "202" ]]; then
            echo -e "  ${GREEN}✓${NC} Admin API 认证成功 (HTTP ${admin_test_code})"
        elif [[ "${admin_test_code}" == "401" ]] || [[ "${admin_test_code}" == "403" ]]; then
            echo -e "  ${RED}✗${NC} Admin Key 无效 (HTTP ${admin_test_code})"
        else
            echo -e "  ${YELLOW}⚠${NC} Admin API 测试返回 HTTP ${admin_test_code} (可能正常)"
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} 未找到 Admin Key, 跳过验证"
    fi

    # 8. HTTPS 域名检查 (可选)
    echo -e "${YELLOW}[8] 域名 HTTPS 检查 (可选)${NC}"
    if command -v curl &>/dev/null; then
        local https_code
        https_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout 3 --max-time 5 -k \
            "https://${DOMAIN}" 2>/dev/null || echo "000")
        if [[ "${https_code}" == "200" ]] || [[ "${https_code}" == "301" ]] || [[ "${https_code}" == "302" ]]; then
            echo -e "  ${GREEN}✓${NC} HTTPS 主站可达 (HTTP ${https_code})"
        elif [[ "${https_code}" == "000" ]]; then
            echo -e "  ${YELLOW}⚠${NC} HTTPS 不可达 (可能 DNS 未解析或无证书)"
        else
            echo -e "  ${RED}✗${NC} HTTPS 返回错误 (HTTP ${https_code})"
            all_ok=0
        fi
    else
        echo -e "  ${YELLOW}⚠${NC} curl 不可用, 跳过 HTTPS 检查"
    fi

    # 汇总报告
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    if [[ ${all_ok} -eq 1 ]]; then
        echo -e "${GREEN}  ✓ 所有检查通过!${NC}"
        echo -e "${GREEN}══════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${CYAN}管理后台访问信息:${NC}"
        echo -e "  ${GREEN}管理后台:${NC}   https://${DOMAIN}/moderation"
        echo -e "  ${GREEN}登录地址:${NC}   https://${DOMAIN}/login"
        echo -e "  ${GREEN}仪表盘:${NC}    https://${DOMAIN}/dashboard"
        echo ""
        echo -e "${YELLOW}注意: 首次使用需要注册账户并提升为管理员${NC}"
        echo -e "  注册: https://${DOMAIN}/register"
        echo -e "  提升: bash ${INSTALL_DIR}/deploy.sh set-admin <用户名>"
    else
        echo -e "${RED}  ✗ 部分检查未通过, 请检查上方错误${NC}"
        echo -e "${RED}══════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}快速修复命令:${NC}"
        echo -e "  bash ${INSTALL_DIR}/deploy.sh diagnose    # 详细诊断"
        echo -e "  bash ${INSTALL_DIR}/deploy.sh fix-nginx    # 修复 Nginx"
        echo -e "  bash ${INSTALL_DIR}/deploy.sh apply-ssl    # 应用 SSL"
    fi
}
diagnose_all() {
    step "系统诊断"

    # 加载环境变量
    local INSTALL_DIR="${INSTALL_DIR:-/www/wwwroot/bbsmc}"
    local ENV_FILE="${INSTALL_DIR}/apps/labrinth/.env"
    [[ ! -f "${ENV_FILE}" ]] && ENV_FILE="${INSTALL_DIR}/bin/.env"
    if [[ -f "${ENV_FILE}" ]]; then
        DOMAIN=$(grep "^DOMAIN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        API_SUBDOMAIN=$(grep "^API_SUBDOMAIN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
        CDN_SUBDOMAIN=$(grep "^CDN_SUBDOMAIN=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2 | tr -d ' "')
    fi
    DOMAIN="${DOMAIN:-bbsmc.org.cn}"
    API_DOMAIN="${API_DOMAIN:-${API_SUBDOMAIN:-api}.${DOMAIN}}"
    CDN_DOMAIN="${CDN_DOMAIN:-${CDN_SUBDOMAIN:-cdn}.${DOMAIN}}"

    local NGINX_CONF_DIR="/www/server/panel/vhost/nginx"
    local nginx_bin
    nginx_bin=$(command -v nginx 2>/dev/null || echo "/usr/sbin/nginx")

    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  BBSMC 系统诊断报告${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""

    # 1. Nginx 状态
    echo -e "${YELLOW}[1] Nginx 状态${NC}"
    local nginx_status
    nginx_status=$(systemctl is-active nginx 2>/dev/null || echo "inactive")
    if [[ "${nginx_status}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} Nginx 运行中"
    else
        echo -e "  ${RED}✗${NC} Nginx 未运行 (状态: ${nginx_status})"
        echo -e "    执行: systemctl start nginx"
    fi

    # 2. Nginx 配置路径
    echo -e "${YELLOW}[2] Nginx 配置路径${NC}"
    local nginx_main
    nginx_main=$("${nginx_bin}" -V 2>&1 | grep -oP '\-\-conf-path=\K[^ ]+' 2>/dev/null || echo "/etc/nginx/nginx.conf")
    echo "  nginx.conf: ${nginx_main}"
    if [[ -f "${nginx_main}" ]]; then
        echo -e "  ${GREEN}✓${NC} 配置文件存在"
    else
        echo -e "  ${RED}✗${NC} 配置文件不存在!"
    fi

    # 3. vhost include 检查
    echo -e "${YELLOW}[3] vhost 目录 include 检查${NC}"
    if [[ -f "${nginx_main}" ]]; then
        if grep -q "vhost/nginx" "${nginx_main}" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} nginx.conf 已 include vhost/nginx 目录"
            grep "vhost/nginx" "${nginx_main}" | while read line; do
                echo "    ${line}"
            done
        else
            echo -e "  ${RED}✗${NC} nginx.conf 未 include vhost/nginx 目录!"
            echo -e "    执行: bash ${0} fix-nginx"
        fi
    fi

    # 4. 0.default.conf 检查
    echo -e "${YELLOW}[4] 默认站点冲突检查${NC}"
    local default_conf="${NGINX_CONF_DIR}/0.default.conf"
    if [[ -f "${default_conf}" ]]; then
        echo -e "  ${RED}⚠${NC} 存在 ${default_conf} (会拦截所有请求!)"
        echo -e "    执行: mv ${default_conf} ${default_conf}.disabled"
        echo -e "    或:   bash ${0} fix-nginx"
    else
        local disabled_conf="${NGINX_CONF_DIR}/0.default.conf.disabled"
        if [[ -f "${disabled_conf}" ]]; then
            echo -e "  ${GREEN}✓${NC} 0.default.conf 已禁用"
        else
            echo -e "  ${GREEN}✓${NC} 无默认站点冲突"
        fi
    fi

    # 5. vhost 配置文件列表
    echo -e "${YELLOW}[5] vhost 配置文件${NC}"
    if [[ -d "${NGINX_CONF_DIR}" ]]; then
        local conf_count=0
        for f in "${NGINX_CONF_DIR}"/*.conf; do
            [[ -f "${f}" ]] || continue
            local fname
            fname=$(basename "${f}")
            local server_names
            server_names=$(grep -oP 'server_name\s+\K[^;]+' "${f}" 2>/dev/null | tr '\n' ',' || echo "")
            local ports
            ports=$(grep -oP 'listen\s+\K[^;]+' "${f}" 2>/dev/null | tr '\n' ',' || echo "")
            if [[ "${fname}" == "0.default.conf" ]]; then
                echo -e "  ${RED}⚠${NC} ${fname}: server_name=[${server_names}] listen=[${ports}]  ← 可能是元凶!"
            elif [[ "${fname}" == _catch_all* ]]; then
                echo -e "  ${GREEN}→${NC} ${fname}: server_name=[${server_names}] listen=[${ports}]  (兜底)"
            else
                echo -e "  ${GREEN}→${NC} ${fname}: server_name=[${server_names}] listen=[${ports}]"
            fi
            conf_count=$((conf_count + 1))
        done
        if [[ ${conf_count} -eq 0 ]]; then
            echo -e "  ${RED}✗${NC} 无任何 vhost 配置文件!"
            echo -e "    执行: bash ${0} fix-nginx"
        fi
    fi

    # 6. Nginx 测试
    echo -e "${YELLOW}[6] Nginx 配置测试${NC}"
    local test_output
    test_output=$("${nginx_bin}" -t 2>&1) || true
    if echo "${test_output}" | grep -q "successful"; then
        echo -e "  ${GREEN}✓${NC} 配置测试通过"
    else
        echo -e "  ${RED}✗${NC} 配置测试失败!"
        echo "  ${test_output}"
        echo -e "    执行: bash ${0} fix-nginx"
    fi

    # 7. 服务状态
    echo -e "${YELLOW}[7] 后端/前端服务${NC}"
    local backend_state frontend_state
    backend_state=$(systemctl is-active bbsmc-labrinth 2>/dev/null || echo "inactive")
    frontend_state=$(systemctl is-active bbsmc-frontend 2>/dev/null || echo "inactive")
    if [[ "${backend_state}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} bbsmc-labrinth (API): active"
    else
        echo -e "  ${RED}✗${NC} bbsmc-labrinth (API): ${backend_state}"
        echo -e "    执行: systemctl restart bbsmc-labrinth"
    fi
    if [[ "${frontend_state}" == "active" ]]; then
        echo -e "  ${GREEN}✓${NC} bbsmc-frontend (前端): active"
    else
        echo -e "  ${RED}✗${NC} bbsmc-frontend (前端): ${frontend_state}"
        echo -e "    执行: systemctl restart bbsmc-frontend"
    fi

    # 8. 本地端口测试
    echo -e "${YELLOW}[8] 端口连通性${NC}"
    local frontend_code backend_code
    frontend_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "http://127.0.0.1:3000" 2>/dev/null || echo "000")
    backend_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 5 "http://127.0.0.1:8000/_internal/health" 2>/dev/null || echo "000")
    if [[ "${frontend_code}" == "000" ]]; then
        echo -e "  ${RED}✗${NC} 前端端口 3000: 无响应"
    else
        echo -e "  ${GREEN}✓${NC} 前端端口 3000: HTTP ${frontend_code}"
    fi
    if [[ "${backend_code}" == "000" ]]; then
        echo -e "  ${RED}✗${NC} 后端端口 8000: 无响应"
    else
        echo -e "  ${GREEN}✓${NC} 后端端口 8000: HTTP ${backend_code}"
    fi

    # 9. SSL 证书
    echo -e "${YELLOW}[9] SSL 证书状态${NC}"
    for domain in "${DOMAIN}" "${API_DOMAIN}" "${CDN_DOMAIN}"; do
        local cert_dir="/www/server/panel/vhost/cert/${domain}"
        if [[ -d "${cert_dir}" ]]; then
            local has_cert=0
            for pattern in "fullchain.pem" "*bundle*" "*.crt"; do
                local matches
                matches=$(find "${cert_dir}" -name "${pattern}" 2>/dev/null | head -1)
                if [[ -n "${matches}" ]]; then
                    has_cert=1
                    echo -e "  ${GREEN}✓${NC} ${domain}: ${matches}"
                    break
                fi
            done
            [[ ${has_cert} -eq 0 ]] && echo -e "  ${RED}✗${NC} ${domain}: 无证书文件"
        else
            echo -e "  ${RED}✗${NC} ${domain}: 证书目录不存在"
        fi
    done

    # 总结
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${YELLOW}快速修复命令:${NC}"
    echo "    bash ${0} fix-nginx    # 修复 Nginx 配置"
    echo "    bash ${0} apply-ssl   # 应用 SSL 证书"
    echo "    journalctl -u bbsmc-frontend -n 50  # 查看前端日志"
    echo "    journalctl -u bbsmc-labrinth -n 50  # 查看后端日志"
    echo ""
}

# 辅助函数: 更新 .env 文件中的指定 key
update_env_key() {
    local file="$1"
    local key="$2"
    local value="$3"
    if grep -q "^${key}=" "${file}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
    else
        echo "${key}=${value}" >> "${file}"
    fi
}

# ---------------------- 主流程 ----------------------
main() {
    # 解析命令行参数
    local action="${1:-install}"

    case "${action}" in
        uninstall|remove)
            uninstall
            exit 0
            ;;
        reinstall|reset)
            # 卸载后重新安装 (默认完整清理, 清除所有数据)
            FORCE_UNINSTALL="${FORCE_UNINSTALL:-1}"
            FULL_PURGE="${FULL_PURGE:-1}"
            uninstall
            echo ""
            info "开始重新部署..."
            echo ""
            ;;
        reconfigure|config)
            # 重新配置 .env 中的第三方服务 (OAuth/SMTP/支付)
            reconfigure_third_party
            exit 0
            ;;
        fix-nginx|nginx)
            # 修复 Nginx 配置 (写入/修复反代配置并启动)
            fix_nginx_configs
            exit 0
            ;;
        apply-ssl|ssl)
            # 应用 SSL 证书到 Nginx (检测已有证书或申请新证书)
            setup_ssl
            echo ""
            info "SSL 证书应用完成!"
            echo "使用浏览器访问 https://${DOMAIN} 验证 SSL 是否生效"
            exit 0
            ;;
        diagnose|diag|check)
            # 诊断 Nginx 和网站问题
            diagnose_all
            exit 0
            ;;
        set-admin|admin)
            # 设置管理员账户 (可接受用户名作为参数)
            shift
            setup_admin_user "$@"
            exit 0
            ;;
        verify-admin|check-admin)
            # 验证后台访问
            verify_admin_access
            exit 0
            ;;
        restart-db|restart-docker|db-restart)
            # 重启所有 Docker 数据库服务
            restart_docker_services
            exit 0
            ;;
        install|"")
            ;;
        *)
            echo "用法: $0 [命令]"
            echo ""
            echo "命令:"
            echo "  install      安装部署 (默认)"
            echo "  reinstall    卸载后重新安装 (清除所有数据和运行时)"
            echo "  fullreset    完整重置 (包括 Rust/Node/Docker/宝塔)"
            echo "  uninstall    卸载 (保留数据需 KEEP_DATA=1)"
            echo "  reconfigure  重新配置第三方服务 (OAuth/SMTP/支付)"
            echo "  fix-nginx    修复 Nginx 反代配置并启动"
            echo "  apply-ssl    应用 SSL 证书到 Nginx (检测已有或申请新证书)"
            echo "  diagnose     系统诊断 (检查 Nginx/服务/端口/SSL 状态)"
            echo "  set-admin    设置管理员账户 (提升用户为 admin 角色)"
            echo "               用法: bash $0 set-admin <用户名> [--confirm]"
            echo "  verify-admin 验证后台访问 (检查后端/前端/API 状态)"
            echo "  restart-db   重启所有 Docker 服务 (PostgreSQL/Redis/Meilisearch/ClickHouse)"
            echo ""
            echo "环境变量:"
            echo "  DOMAIN              主域名 (如 bbsmc.org.cn)"
            echo "  API_SUBDOMAIN       API 子域名 (默认 api)"
            echo "  CDN_SUBDOMAIN       CDN 子域名 (默认 cdn)"
            echo "  INSTALL_DIR         安装目录 (默认 /www/wwwroot/bbsmc)"
            echo "  DATA_DIR            数据目录 (默认 /www/wwwroot/bbsmc-data)"
            echo "  MIRROR_MODE         Modrinth 镜像模式 (1=启用)"
            echo "  FORCE_UNINSTALL     跳过卸载确认 (1=跳过)"
            echo "  FULL_PURGE          完整清理运行时 (1=清除 Rust/Node/Docker/宝塔)"
            echo "  KEEP_DATA           卸载时保留数据 (1=保留)"
            echo "  SKIP_BUILD_PREPARE  前端构建跳过 API 预取 (1=跳过)"
            echo "  AUTO_ACCEPT         已有配置时自动确认继续 (1=自动)"
            echo ""
            echo "注意: 重新运行脚本会自动从已有 .env 恢复域名/OAuth/SMTP 等配置"
            echo ""
            echo "OAuth/第三方服务 (可在部署时交互输入, 也可通过环境变量预置):"
            echo "  GITHUB_CLIENT_ID / GITHUB_CLIENT_SECRET"
            echo "  MICROSOFT_CLIENT_ID / MICROSOFT_CLIENT_SECRET"
            echo "  GITLAB_CLIENT_ID / GITLAB_CLIENT_SECRET"
            echo "  DISCORD_CLIENT_ID / DISCORD_CLIENT_SECRET"
            echo "  GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET"
            echo "  BILIBILI_CLIENT_ID / BILIBILI_CLIENT_SECRET"
            echo "  QQ_CLIENT_ID / QQ_CLIENT_SECRET"
            echo "  SMTP_HOST / SMTP_USERNAME / SMTP_PASSWORD"
            echo "  PAYPAL_CLIENT_ID / PAYPAL_CLIENT_SECRET"
            echo "  STRIPE_API_KEY / STRIPE_WEBHOOK_SECRET"
            exit 0
            ;;
    esac

    echo -e "${CYAN}"
    echo "============================================================"
    echo "   BBSMC 一键部署脚本 (宝塔 Ubuntu 8H8G)"
    echo "   项目: https://github.com/xcqm12/app"
    echo "============================================================"
    echo -e "${NC}"

    collect_input
    check_system
    setup_swap
    install_baota
    install_dependencies
    install_docker
    install_nodejs
    install_rust
    clone_repo
    start_databases
    gen_env_files
    build_backend
    run_migrations
    # 先启动后端, 让前端 build:before 能获取 API 数据
    setup_systemd_labrinth
    wait_for_backend
    build_frontend
    setup_systemd_frontend
    setup_nginx
    setup_ssl
    setup_modrinth_mirror
    setup_firewall
    post_deploy_verify
    print_summary
}

main "$@"
