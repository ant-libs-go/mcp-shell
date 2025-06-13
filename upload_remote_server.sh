#!/bin/bash

# 实现 scp 上传功能
# Env: 
#   REMOTE_TARGET: 远程服务器地址，格式为 user@host:port/path/
# Param:
#   content: 文件内容，require
#   filename: 文件名，require

# 确保系统已安装 scp 工具用于文件传输
if ! command -v scp &> /dev/null; then
    send_error -32000 "Command [scp] is required. Please install it"
    exit 1
fi

# 注册工具函数
register_tool "upload_remote_server" '
{
    "name": "upload_remote_server",
    "description": "将内容写入临时文件并通过SCP上传到远程服务器",
    "inputSchema": {
        "type": "object",
        "properties": {
            "content": {
                "type": "string",
                "description": "要上传的文件内容"
            },
            "filename": {
                "type": "string",
                "description": "上传后的文件名"
            }
        },
        "required": ["content", "filename"]
    }
}'

# 上传函数，函数名必须与注册的工具名称一致
# 参数: $1 - 文件内容, $2 - 文件名, $3 - 远程主机
upload_remote_server() {
    # 从参数中提取上传所需的各项参数
    local content=$(echo "$arguments" | jq -r '.content // empty')
    local filename=$(echo "$arguments" | jq -r '.filename // empty')
    local remote_target="${REMOTE_TARGET}"

    # 验证必需参数
    if [ -z "$content" ] || [ -z "$filename" ] || [ -z "$remote_target" ]; then
        echo "Content, filename and Env[REMOTE_TARGET] are required"
        return 1
    fi
    
    # 解析远程目标格式 (user@host:/path/ 或 user@host:port/path/)
    local port=""
    local target=""

    if [[ ! "$remote_target" =~ ^([^:]+@[^:]+):([0-9]*)(/.*)?$ ]]; then
        echo "The remote server settings are incorrect. The expected format is: user@host:port/path/"
        return 1
    fi 
    port="${BASH_REMATCH[2]:-22}" # 端口号，默认 22
    target="${BASH_REMATCH[1]}:${BASH_REMATCH[3]}/${filename}" # 构造清理后的路径

    # 创建临时文件
    local temp_file
    temp_file=$(mktemp) || {
        echo "Failed to create a temporary file"
        return 1
    }
    
    # 将内容写入临时文件
    printf "%s" "$content" > "$temp_file" || {
        echo "Failed to write to the temporary file: $temp_file"
        rm -f "$temp_file"
        return 1
    }
    
    # 执行SCP上传命令
    local scp_result=$(scp -P "$port" "$temp_file" "$target" 2>&1)
    local scp_exit_code=$?
    
    # 清理临时文件
    rm -f "$temp_file"
    
    # 检查SCP命令执行结果
    if [ $scp_exit_code -eq 0 ]; then
        echo "Successfully uploaded to ${remote_target}"
        return 0
    else
        echo "Upload failed: $scp_result"
        return 1
    fi
}