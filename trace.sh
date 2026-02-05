#!/bin/bash

# 这个是 trace.sh 的完整版本，用于生成 trace_menu.sh
# 它会下载/创建带 IPv6 支持的菜单脚本，并自动运行
# 支持依赖检查、IPv4/IPv6 自动切换、ASN 查询

# 先检查并安装依赖（traceroute, jq, curl）
echo "正在检查并安装依赖..."
for cmd in traceroute jq curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "安装 $cmd ..."
        sudo apt-get update -qq && sudo apt-get install -y $cmd 2>/dev/null || \
        sudo yum install -y $cmd 2>/dev/null || \
        sudo dnf install -y $cmd 2>/dev/null
    fi
done

# 创建 trace_menu.sh 文件
cat << 'EOF' > trace_menu.sh
#!/bin/bash

# 强制显示报错
set -e

# 检查并安装必要组件（冗余检查，以防万一）
echo "正在检查环境..."
for cmd in traceroute jq curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "安装依赖: $cmd"
        sudo apt-get update && sudo apt-get install -y $cmd || sudo yum install -y $cmd || sudo dnf install -y $cmd
    fi
done

echo "========================================================="
echo "        VPS 回程路由追踪 (带 ASN 信息) - 支持 IPv4/IPv6"
echo "========================================================="
echo "1) 上海联通 IPv4 (网关) "
echo "2) 上海联通 IPv4 (家宽) "
echo "3) 上海电信 IPv4 (CN2) "
echo "4) 上海移动 IPv4       "
echo "5) 上海联通 IPv6       "
echo "6) 上海电信 IPv6       "
echo "7) 上海移动 IPv6       "
echo "8) 手动输入目标 (支持 IPv4/IPv6/域名)"
echo "========================================================="
read -p "请选择 (1-8): " CHOICE

#139.226.225.150 139.226.210.90
case $CHOICE in
    1) TARGET="210.22.97.1" ;;
    2) TARGET="139.226.210.90" ;;
    3) TARGET="202.96.209.133" ;;
    4) TARGET="211.136.112.200" ;;
    5) TARGET="2408:870c:4000::11" ;;   
    6) TARGET="240e:928:1000::1" ;;
    7) TARGET="2409:8c1e:75b0:3003::26" ;;
    8) read -p "请输入 IP 或域名 (支持 IPv4/IPv6): " TARGET ;;
    *) echo "无效选择，退出..."; exit 1 ;;
esac

echo -e "\n正在追踪到 $TARGET ...\n"

# 自动选择 IPv4 或 IPv6 模式
if [[ $TARGET == *":"* ]]; then
    PROTOCOL="-6"
    echo "(检测到 IPv6 地址，使用 traceroute -6)"
else
    PROTOCOL="-4"
    echo "(使用 IPv4 模式 traceroute -4)"
fi

printf "%-3s  %-40s  %-10s  %-30s\n" "跳数" "IP 地址" "延迟" "ASN/运营商归属"
echo "--------------------------------------------------------------------------------"

traceroute $PROTOCOL -n -w 1 -q 1 "$TARGET" | tail -n +2 | while read -r line; do
    HOP=$(echo "$line" | awk '{print $1}')
    IP=$(echo "$line" | awk '{print $2}')
    TIME=$(echo "$line" | awk '{print $3}')

    if [[ "$IP" == "*" ]] || [ -z "$IP" ] || [[ "$IP" == "ms" ]]; then
        printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "*" "*" "***"
        continue
    fi

    # 使用 curl -i 取得 headers + body
    response=$(curl -s -i --max-time 5 "http://ip-api.com/json/${IP}?fields=status,as,org,regionName" 2>/dev/null)

    # 分離 headers 和 body
    headers=$(echo "$response" | sed '/^\r$/q' | head -n -1)
    body=$(echo "$response" | sed '1,/^\r$/d')

    # 解析 X-Rl 和 X-Ttl（忽略大小寫）
    remaining=$(echo "$headers" | grep -i '^X-Rl:' | awk '{print $2}' | tr -d '\r')
    ttl=$(echo "$headers" | grep -i '^X-Ttl:' | awk '{print $2}' | tr -d '\r')

    # 如果無法解析，預設安全值
    remaining=${remaining:-45}
    ttl=${ttl:-0}

    # 接近限額時等待（剩餘 ≤5 次，或 X-Rl=0）
    if (( remaining <= 5 )) || [[ "$remaining" == "0" ]]; then
        wait_sec=${ttl:-2}  # 至少等 2 秒
        echo "    IP-API 剩餘請求少 ($remaining)，等待 ${wait_sec} 秒避免限速..."
        sleep "$wait_sec"
    fi

    # 使用 body 繼續解析（若 curl 完全失敗，body 會是空）
    if [[ -z "$body" ]] || [[ $(echo "$body" | jq -r '.status // "fail"') != "success" ]]; then
        printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "局域网/未知节点"
        continue
    fi

    ASN=$(echo "$body" | jq -r '.as' | awk '{print $1}' || echo "未知")
    ORG=$(echo "$body" | jq -r '.org // "未知"' )
    REG=$(echo "$body" | jq -r '.regionName // ""')

    if [ -n "$REG" ]; then
        printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "[$ASN] $ORG ($REG)"
    else
        printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "[$ASN] $ORG"
    fi
    

    # 查询 ASN 信息
    # INFO=$(curl -s --max-time 3 "http://ip-api.com/json/${IP}?fields=status,as,org,regionName" || echo '{"status":"fail"}')
    #if [[ $(echo "$INFO" | jq -r '.status // "fail"') == "success" ]]; then
    #    ASN=$(echo "$INFO" | jq -r '.as' | awk '{print $1}' || echo "未知")
    #    ORG=$(echo "$INFO" | jq -r '.org // "未知"' )
    #    REG=$(echo "$INFO" | jq -r '.regionName // ""')
    #    if [ -n "$REG" ]; then
    #        printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "[$ASN] $ORG ($REG)"
    #    else
    #        printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "[$ASN] $ORG"
    #    fi
    #else
    #    printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "局域网/未知节点"
    #fi
    
done

echo ""
echo "追踪完成。"
EOF

chmod +x trace_menu.sh
echo "腳本已生成 → ./trace_menu.sh"
echo "正在启动..."
./trace_menu.sh
