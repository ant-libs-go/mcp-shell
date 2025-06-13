#!/bin/bash
# Ant-Mcp-Shell

# 定义工具列表
declare -A tools

# 日志输出函数
# 参数: $1 - 日志消息
log() {
    echo "[Ant-Mcp-Shell] $1" >> /tmp/run.log
}

# 发送 JSON-RPC 响应函数
# 参数: $1 - 请求ID, $2 - 结果数据
send_response() {
    local id="$1"
    local result="$2"
    local response
    
    # 根据结果是否为 null 构造不同的响应格式
    if [ "$result" = "null" ]; then
        response='{"jsonrpc": "2.0", "id": '"$id"', "result": null}'
    else
        response='{"jsonrpc": "2.0", "id": '"$id"', "result": '"$result"'}'
    fi
    
    response=$(printf '%s' "$response" | tr -d ' \t\n')
    log "Response: $response"
    echo "$response"
}

# 发送 JSON-RPC 错误响应函数
# 参数: $1 - 请求ID, $2 - 错误代码, $3 - 错误消息
send_error() {
    local id="$1"
    local code="$2"
    local message="$3"
    local response='{"jsonrpc": "2.0", "id": '"$id"', "error": {"code": '"$code"', "message": "'"$message"'"}}'

    response=$(printf '%s' "$response" | tr -d ' \t\n')
    log "Exception：$response"
    echo "$response"
}

# 注册工具函数
# 参数: $1 - 工具名称, $2 - 工具定义
register_tool() {
    local name="$1"
    local tool="$2"

    tools["$name"]="$tool"
}

# 依赖工具包检查
if ! command -v jq &> /dev/null; then
    send_error -32000 "Command [jq] is required. Please install it"
    exit 1
fi

# 注册工具
source ./upload_remote_server.sh

# 处理初始化请求
# 返回服务器的基本信息和能力声明
handle_initialize() {
    local id="$1"
    local result='{
        "protocolVersion": "2024-11-05",
        "capabilities": {
            "tools": {}
        },
        "serverInfo": {
            "name": "Ant-Mcp-Shell-Server",
            "version": "1.0.0"
        }
    }'
    send_response "$id" "$result"
}

# 处理工具列表请求
# 返回服务器支持的所有工具及其说明
handle_tools_list() {
    local id="$1"

    result='{"tools": ['
    first=true
    for tool in "${tools[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            result="$result,"
        fi
        result="$result$tool"
    done

    result="$result]}"
    send_response "$id" "$result"
}

# 处理工具调用请求
# 参数: $1 - 请求ID, $2 - 工具名称, $3 - 工具参数
handle_tools_call() {
    local id="$1"
    local name="$2"
    local arguments="$3"

    if [[ ! -v tools["$name"] ]]; then
        send_error "$id" -32601 "Unknown tool: $name"
        return
    fi

    local result=$($name 2>&1)
    local exit_code=$?
    
    # 根据执行结果返回响应或错误
    if [ $exit_code -eq 0 ]; then
        local response_content='{
            "content": [
                {
                    "type": "text",
                    "text": "'"$result"'"
                }
            ]
        }'
        send_response "$id" "$response_content"
    else
        send_error "$id" -32000 "$result"
    fi
}

# 主消息处理循环
log "Ant-Mcp-Shell Server has been started"

# 持续读取标准输入的消息并处理
while IFS= read -r line; do
    # 跳过空行
    [ -z "$line" ] && continue
    
    log "Request: $line"
    
    # 解析 JSON-RPC 消息的各个字段
    method=$(echo "$line" | jq -r '.method // empty')
    id=$(echo "$line" | jq -r '.id // empty')
    params=$(echo "$line" | jq -r '.params // {}')
    
    # 验证消息格式
    if [ -z "$method" ]; then
        log "Unknown request: method is not specified"
        continue
    fi
    
    # 根据方法名分发处理
    case "$method" in
        "initialize")
            # 处理初始化请求
            handle_initialize "$id"
            ;;
            
        "tools/list")
            # 处理工具列表请求
            handle_tools_list "$id"
            ;;
            
        "tools/call")
            # 处理工具调用请求
            name=$(echo "$params" | jq -r '.name // empty')
            arguments=$(echo "$params" | jq -r '.arguments // {}')
            handle_tools_call "$id" "$name" "$arguments"
            ;;
            
        *)
            # 未知方法
            send_error "$id" -32601 "Unknown method: $method"
            ;;
    esac
done

log "Ant-Mcp-Shell Server has stopped"
