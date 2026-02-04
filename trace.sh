cat << 'EOF' > trace_menu.sh
#!/bin/bash

# 强制显示报错
set -e

# 检查并安装必要组件
echo "正在检查环境..."
for cmd in traceroute jq curl; do
    if ! command -v $cmd &> /dev/null; then
        echo "安装依赖: $cmd"
        sudo apt-get update && sudo apt-get install -y $cmd || sudo yum install -y $cmd
    fi
done


echo "========================================================="
echo "        VPS 回程路由追踪 (带 ASN 信息) - 支持 IPv4/IPv6"
echo "========================================================="
echo "1) 上海联通 IPv4 (网关)     - 210.22.70.225"
echo "2) 上海联通 IPv4 (家宽)     - 58.247.248.7"
echo "3) 上海电信 IPv4 (CN2)      - 58.32.0.1"
echo "4) 上海移动 IPv4            - 221.183.55.22"
echo "5) 上海联通 IPv6            - 2408:80f1:21:5003::a"
echo "6) 上海电信 IPv6            - 240e:928:1000::1"
echo "7) 上海移动 IPv6            - 2409:8c1e:75b0:3003::26"
echo "8) 手动输入目标 (支持 IPv4/IPv6/域名)"
echo "========================================================="
read -p "请选择 (1-8): " CHOICE

case $CHOICE in
    1) TARGET="210.22.70.225" ;;
    2) TARGET="58.247.248.7" ;;
    3) TARGET="58.32.0.1" ;;
    4) TARGET="221.183.55.22" ;;
    5) TARGET="2408:80f1:21:5003::a" ;;
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
        printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "*" "*" "请求超时"
        continue
    fi

    # 查询 ASN 信息
    INFO=$(curl -s --max-time 3 "http://ip-api.com/json/${IP}?fields=status,as,org,regionName" || echo '{"status":"fail"}')
    
    if [[ $(echo "$INFO" | jq -r '.status // "fail"') == "success" ]]; then
        ASN=$(echo "$INFO" | jq -r '.as' | awk '{print $1}' || echo "未知")
        ORG=$(echo "$INFO" | jq -r '.org // "未知"' )
        REG=$(echo "$INFO" | jq -r '.regionName // ""')
        if [ -n "$REG" ]; then
            printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "[$ASN] $ORG ($REG)"
        else
            printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "[$ASN] $ORG"
        fi
    else
        printf "%-3s  %-40s  %-10s  %-30s\n" "$HOP" "$IP" "${TIME}ms" "局域网/未知节点"
    fi
done

EOF

# 如果上面成功生成了 trace_menu.sh，再单独跑：
chmod +x trace_menu.sh
./trace_menu.sh
