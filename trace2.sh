#!/bin/bash

# 修改版 trace.sh：ASN 查询改用 https://ipinfo.io/{IP}/json（遗留免费接口）
# 注意：无 token 每天约 1000 次（共享 IP 限额），高频建议注册免费 token 后改用带 token 的 api.ipinfo.io
# 原作者 Memory2014，修改：替换 ASN 来源 + 解析逻辑

echo "正在检查并安装依赖..."
for cmd in traceroute jq curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "安装 $cmd ..."
        sudo apt-get update -qq && sudo apt-get install -y $cmd 2>/dev/null || \
        sudo yum install -y $cmd 2>/dev/null || \
        sudo dnf install -y $cmd 2>/dev/null
    fi
done

# 创建 trace_menu.sh 文件（核心修改在这里）
cat << 'EOF' > trace_menu.sh
#!/bin/bash

set -e

echo "正在检查环境..."
for cmd in traceroute jq curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "安装依赖: $cmd"
        sudo apt-get update && sudo apt-get install -y $cmd || sudo yum install -y $cmd || sudo dnf install -y $cmd
    fi
done

echo "========================================================="
echo "        VPS 回程路由追踪 - 支持 IPv4/IPv6 (ASN来源ipinfo.io) "
echo "========================================================="
echo "1) 上海联通 IPv4 (网关) "
echo "2) 上海联通 IPv4 "
echo "3) 上海电信 IPv4 "
echo "4) 上海移动 IPv4 "
echo "5) 上海联通 IPv6 "
echo "6) 上海电信 IPv6 "
echo "7) 上海移动 IPv6 "
echo "8) 手动输入目标 (支持 IPv4/IPv6/域名)"
echo "========================================================="
read -p "请选择 (1-8): " CHOICE

case $CHOICE in
    1) TARGET="210.22.97.1" ;;
    2) TARGET="139.226.210.90" ;;
    3) TARGET="101.95.88.153" ;;
    4) TARGET="211.136.112.252" ;;
    5) TARGET="2408:870c:4000::11" ;;   
    6) TARGET="240e:928:1000::1" ;;
    7) TARGET="2409:801e:f0:1::1c9" ;;
    8) read -p "请输入 IP 或域名 (支持 IPv4/IPv6): " TARGET ;;
    *) echo "无效选择，退出..."; exit 1 ;;
esac

echo -e "\n正在追踪到 $TARGET ...\n"

if [[ $TARGET == *":"* ]]; then
    PROTOCOL="-6"
    echo "(检测到 IPv6 地址，使用 traceroute -6)"
else
    PROTOCOL="-4"
    echo "(使用 IPv4 模式 traceroute -4)"
fi

printf "%-3s %-40s %-10s %-40s\n" "跳数" "IP 地址" "延迟" "ASN/运营商归属"
echo "------------------------------------------------------------------------------------------"

traceroute $PROTOCOL -n -w 1 -q 1 "$TARGET" | tail -n +2 | while read -r line; do
    HOP=$(echo "$line" | awk '{print $1}')
    IP=$(echo "$line" | awk '{print $2}')
    TIME=$(echo "$line" | awk '{print $3}')

    if [[ "$IP" == "*" ]] || [ -z "$IP" ] || [[ "$IP" == "ms" ]]; then
        printf "%-3s %-40s %-10s %-40s\n" "$HOP" "*" "*" "***"
        continue
    fi

    # 查询 ipinfo.io 遗留接口（无 token）
    INFO=$(curl -s --max-time 4 "https://ipinfo.io/${IP}/json" 2>/dev/null || echo '{"org":"查询失败"}')

    # 检查是否成功解析（ipinfo 失败时通常返回纯文本错误或空 JSON）
    if [[ "$INFO" == *"rate limit"* ]] || [[ "$INFO" == *"429"* ]] || ! echo "$INFO" | jq . >/dev/null 2>&1; then
        printf "%-3s %-40s %-10s %-40s\n" "$HOP" "$IP" "${TIME}ms" "查询超限或失败"
        continue
    fi

    ORG=$(echo "$INFO" | jq -r '.org // "未知"')
    if [[ "$ORG" == "null" || -z "$ORG" ]]; then
        ASN="未知"
        ORG_FULL="未知节点 / 局域网"
    else
        # ipinfo 的 org 通常是 "ASxxxxxx Provider Name"
        ASN=$(echo "$ORG" | awk '{print $1}' | grep -o '^AS[0-9]\+' || echo "未知")
        ORG_FULL=$(echo "$ORG" | sed 's/^AS[0-9]\+ //')
        [[ -z "$ORG_FULL" ]] && ORG_FULL="$ORG"
    fi

    # 可选：如果有 city/region/country，可拼接更多信息
    # CITY=$(echo "$INFO" | jq -r '.city // ""')
    # if [ -n "$CITY" ]; then ORG_FULL="$ORG_FULL ($CITY)"; fi

    printf "%-3s %-40s %-10s %-40s\n" "$HOP" "$IP" "${TIME}ms" "[$ASN] $ORG_FULL"
done

echo ""
echo "追踪完成。"
EOF

chmod +x trace_menu.sh
echo "脚本已生成 → ./trace_menu.sh"
echo "正在启动..."
./trace_menu.sh
