# SMB Client Prometheus Exporter

这个 PowerShell 脚本将 Windows 性能计数器中的 SMB Client 信息转换为 Prometheus textfile 格式。

## 功能

- 收集 SMB Client Shares 性能计数器数据
- 将数据转换为 Prometheus 标准格式
- 支持按共享（share）标签分组
- 原子性文件写入，避免读取时文件损坏

## 使用方法

### 基本用法

```powershell
.\smb-client-exporter.ps1
```

### 自定义输出路径

```powershell
.\smb-client-exporter.ps1 -OutputPath "D:\metrics\smb_client.prom"
```

### 作为计划任务运行

#### 方法 1：使用自动化脚本（推荐）

以管理员身份运行：

```powershell
.\setup-scheduled-task.ps1 -IntervalMinutes 1
```

这将创建一个每 1 分钟运行一次的计划任务。

#### 方法 2：手动创建计划任务

1. 打开"任务计划程序"（Task Scheduler）
2. 创建基本任务
3. 触发器：设置为每 60 秒运行一次
4. 操作：启动程序
   - 程序：`powershell.exe`
   - 参数：`-ExecutionPolicy Bypass -File "C:\path\to\smb-client-exporter.ps1"`
   - 起始于：脚本所在目录

### 测试脚本

运行测试脚本验证功能：

```powershell
.\test-exporter.ps1
```

这将：
- 运行导出脚本
- 检查输出文件
- 验证 Prometheus 格式
- 显示文件内容预览

### 配置 Prometheus

在 Prometheus 配置文件中，确保 node_exporter 启用了 textfile collector：

```yaml
scrape_configs:
  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
```

在 node_exporter 启动时添加参数：

```bash
node_exporter --collector.textfile.directory="C:\prometheus\textfile"
```

## 导出的指标

脚本会导出以下 SMB Client 指标：

- `smb_client_bytes_read_per_sec{share="<share_name>"}` - 每个共享的读取字节数/秒
- `smb_client_bytes_written_per_sec{share="<share_name>"}` - 每个共享的写入字节数/秒
- `smb_client_read_bytes_per_sec{share="<share_name>"}` - 每个共享的读取字节数/秒
- `smb_client_write_bytes_per_sec{share="<share_name>"}` - 每个共享的写入字节数/秒
- `smb_client_read_requests_per_sec{share="<share_name>"}` - 每个共享的读取请求数/秒
- `smb_client_write_requests_per_sec{share="<share_name>"}` - 每个共享的写入请求数/秒
- `smb_client_current_data_queue_length{share="<share_name>"}` - 每个共享的当前数据队列长度
- `smb_client_data_bytes_per_sec{share="<share_name>"}` - 每个共享的数据字节数/秒
- `smb_client_data_requests_per_sec{share="<share_name>"}` - 每个共享的数据请求数/秒

以及全局总计指标（无 share 标签）。

## 文件格式

输出文件符合 Prometheus textfile 格式标准：

```
# HELP smb_client_bytes_read_per_sec SMB Client bytes_read_per_sec for share \\server\share
# TYPE smb_client_bytes_read_per_sec gauge
smb_client_bytes_read_per_sec{share="\\\\server\\share"} 1234.56 1234567890123
```

## 注意事项

1. 需要管理员权限才能读取性能计数器
2. 确保输出目录存在且有写入权限
3. 建议使用计划任务定期运行脚本（例如每 60 秒）
4. 文件使用 UTF-8 编码

## 故障排除

如果脚本无法读取计数器，请检查：

1. 是否以管理员身份运行
2. SMB Client 服务是否正在运行
3. 性能计数器是否可用：`Get-Counter -ListSet "SMB Client Shares"`

