#!/bin/bash
SH_PATH=$(cd "$(dirname "$0")";pwd)
cd ${SH_PATH}

create_mainfest_file(){
    echo "进行配置。。。"
    read -p "请输入你的应用名称：" IBM_APP_NAME
    echo "应用名称：${IBM_APP_NAME}"
    read -p "请输入你的应用内存大小(默认256)：" IBM_MEM_SIZE
    if [ -z "${IBM_MEM_SIZE}" ];then
        IBM_MEM_SIZE=256
    fi
    echo "内存大小：${IBM_MEM_SIZE}"
    #read -p "请输入V2ray协议类型：" V2RAY_PROTOCAL
    V2RAY_PROTOCAL=vmess
    echo "V2ray协议类型：" ${V2RAY_PROTOCAL}
    UUID=$(cat /proc/sys/kernel/random/uuid)
    echo "生成随机UUID：${UUID}"
    read -p "请输入路径（空，自动生成）：" V2RAY_PATH
    if [ -z "${V2RAY_PATH}" ];then
        V2RAY_PATH=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
    fi
    echo "V2ray WebSocket路径：${V2RAY_PATH}"
    
    cat >  ${SH_PATH}/cloud/v2ray-cloudfoundry/manifest.yml  << EOF
    applications:
    - path: .
      name: ${IBM_APP_NAME}
      random-route: false
      buildpack: go_buildpack
      command: ./v2ray/v2ray -config ./v2ray/config.json
      health-check-type: port
      memory: ${IBM_MEM_SIZE}M
EOF

    cat >  ${SH_PATH}/cloud/v2ray-cloudfoundry/v2ray/config.json  << EOF
    {
        "inbounds": [
            {
                "port": 8080,
                "protocol": "${V2RAY_PROTOCAL}",
                "settings": {
                    "clients": [
                        {
                            "id": "${UUID}",
                            "alterId": 64
                        }
                    ]
                },
                "streamSettings": {
                    "network":"ws",
                    "wsSettings": {
                        "path": "${V2RAY_PATH}"
                    }
                }
            }
        ],
        "outbounds": [
            {
                "protocol": "freedom",
                "settings": {}
            }
        ]
    }
EOF
    echo "配置完成。"
}

clone_repo(){
    echo "进行初始化。。。"
    git clone https://github.com/adoom2017/cloud
    cd cloud/bin/v2ray
    
    # Script from https://github.com/v2fly/fhs-install-v2ray/blob/master/install-release.sh
    # Get V2Ray release version number
    TMP_FILE="$(mktemp)"
    if ! curl -s -o "$TMP_FILE" 'https://api.github.com/repos/v2fly/v2ray-core/releases/latest'; then
        rm "$TMP_FILE"
        echo 'error: 获取最新V2Ray版本号失败。请重试'
        exit 1
    fi
    RELEASE_LATEST="$(sed 'y/,/\n/' "$TMP_FILE" | grep 'tag_name' | awk -F '"' '{print $4}')"
    rm "$TMP_FILE"
    echo "当前最新V2Ray版本为$RELEASE_LATEST"
    # Download latest release
    DOWNLOAD_LINK="https://github.com/v2fly/v2ray-core/releases/download/$RELEASE_LATEST/v2ray-linux-64.zip"
    if ! curl -L -H 'Cache-Control: no-cache' -o "latest-v2ray.zip" "$DOWNLOAD_LINK"; then
        echo 'error: 下载V2Ray失败，请重试'
        return 1
    fi
    unzip latest-v2ray.zip v2ray v2ctl geoip.dat geosite.dat
    rm latest-v2ray.zip
    
    chmod 0755 ./*
    cd ${SH_PATH}/cloud/bin
    echo "初始化完成。"
}

install(){
    echo "进行安装。。。"
    cd ${SH_PATH}/cloud/bin
    ibmcloud target --cf
    echo "y" | ibmcloud cf install
    ibmcloud cf push
    echo "安装完成。"
    echo "UUID：${UUID}"
    echo "WebSocket路径：${V2RAY_PATH}"
    VMESSCODE=$(base64 -w 0 << EOF
    {
      "v": "2",
      "ps": "${IBM_HOST_NAME}",
      "add": "${IBM_HOST_NAME}.us-south.cf.appdomain.cloud",
      "port": "443",
      "id": "${UUID}",
      "aid": "64",
      "net": "ws",
      "type": "none",
      "host": "",
      "path": "${V2RAY_PATH}",
      "tls": "tls"
    }
EOF
    )
	echo "配置链接："
    echo vmess://${VMESSCODE}

}

clone_repo
create_mainfest_file
install
exit 0
