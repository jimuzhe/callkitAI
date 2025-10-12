# 闹钟服务端 API

基于 Python Flask 的闹钟数据管理服务，支持闹钟的增删改查操作，数据持久化到 MySQL 数据库。

## 功能特性

- ✅ 闹钟的增删改查操作
- ✅ 支持闹钟启用/禁用状态切换
- ✅ 支持按用户查询闹钟
- ✅ 支持重复闹钟设置（周一到周日）
- ✅ RESTful API 设计
- ✅ MySQL 数据持久化
- ✅ CORS 跨域支持
- ✅ Swagger API 文档自动生成

## 技术栈

- Python 3.8+
- Flask 3.0
- MySQL 5.7+
- PyMySQL
- Flasgger (Swagger/OpenAPI)

## 项目结构

```
server/
├── app.py              # Flask 应用主文件
├── config.py           # 配置文件
├── database.py         # 数据库连接管理
├── models.py           # 数据模型
├── dao.py              # 数据访问层
├── init_db.sql         # 数据库初始化脚本
├── requirements.txt    # Python 依赖
├── .env.example        # 环境变量示例
└── README.md           # 项目文档
```

## 快速开始

### 1. 安装依赖

```bash
cd server
pip install -r requirements.txt
```

### 2. 配置数据库

复制 `.env.example` 为 `.env` 并修改数据库配置：

```bash
cp .env.example .env
```

编辑 `.env` 文件：

```env
DB_HOST=localhost
DB_PORT=3306
DB_USER=root
DB_PASSWORD=你的密码
DB_NAME=alarm_clock_db
```

### 3. 初始化数据库

使用 MySQL 客户端执行初始化脚本：

```bash
mysql -u root -p < init_db.sql
```

或者在 MySQL 命令行中：

```sql
source init_db.sql;
```

### 4. 启动服务

```bash
python app.py
```

服务将在 `http://localhost:5000` 启动。

## API 接口文档

### Swagger UI

启动服务后，可以通过以下地址访问交互式的 API 文档：

```
http://localhost:5000/apidocs/
```

Swagger UI 提供了：
- 完整的 API 接口列表
- 每个接口的详细参数说明
- 交互式测试功能
- 请求/响应示例

### 基础信息

- **Base URL**: `http://localhost:5000`
- **Content-Type**: `application/json`

---

## API 列表

### 1. 健康检查

**描述**: 检查服务是否正常运行。

- **方法**: `GET`
- **路径**: `/health`

**响应示例**:
```json
{
  "success": true,
  "message": "服务运行正常",
  "data": null
}
```

---

### 2. 创建闹钟

**描述**: 创建一个新的闹钟。

- **方法**: `POST`
- **路径**: `/api/alarms`
- **请求体**:
```json
{
  "alarm_id": "550e8400-e29b-41d4-a716-446655440001",
  "user_id": "user_001",
  "alarm_time": "07:30",
  "alarm_name": "早晨闹钟",
  "ai_persona_id": "gentle",
  "repeat_days": "1,2,3,4,5",
  "is_enabled": true
}
```

**响应示例**:
```json
{
  "success": true,
  "message": "闹钟创建成功",
  "data": {
    "alarm_id": 1
  }
}
```

---

### 3. 获取单个闹钟

**描述**: 根据闹钟 ID 获取闹钟详情。

- **方法**: `GET`
- **路径**: `/api/alarms/{alarm_id}`

**响应示例**:
```json
{
  "success": true,
  "message": "操作成功",
  "data": {
    "alarm_id": "550e8400-e29b-41d4-a716-446655440001",
    "user_id": "user_001",
    "alarm_time": "07:30",
    "alarm_name": "早晨闹钟",
    "ai_persona_id": "gentle",
    "repeat_days": "1,2,3,4,5",
    "is_enabled": true,
    "next_alarm_time": null,
    "created_at": "2025-10-11T10:30:00",
    "updated_at": "2025-10-11T10:30:00"
  }
}
```

---

### 4. 获取闹钟列表

**描述**: 获取所有闹钟或按条件筛选闹钟。

- **方法**: `GET`
- **路径**: `/api/alarms`
- **查询参数**:
  - `user_id` (可选): 按用户 ID 筛选
  - `enabled_only` (可选): 仅获取启用的闹钟，值为 `1` 表示启用

**示例**:
```
GET /api/alarms?user_id=user_001
GET /api/alarms?enabled_only=1
```

**响应示例**:
```json
{
  "success": true,
  "message": "操作成功",
  "data": [
    {
      "alarm_id": 1,
      "user_id": "user_001",
      "alarm_time": "07:30",
      "title": "早晨闹钟",
      "is_enabled": true
    }
  ]
}
```

---

### 5. 更新闹钟

**描述**: 更新指定闹钟的信息。

- **方法**: `PUT`
- **路径**: `/api/alarms/{alarm_id}`
- **请求体**:
```json
{
  "user_id": "user_001",
  "alarm_time": "08:00",
  "title": "更新后的闹钟",
  "ai_persona": "你是一位专业的时间管理助手，会用简洁高效的语言提醒用户",
  "repeat_days": "1,2,3,4,5,6,7",
  "is_enabled": true
}
```

**响应示例**:
```json
{
  "success": true,
  "message": "闹钟更新成功",
  "data": null
}
```

---

### 6. 删除闹钟

**描述**: 删除指定闹钟。

- **方法**: `DELETE`
- **路径**: `/api/alarms/{alarm_id}`

**响应示例**:
```json
{
  "success": true,
  "message": "闹钟删除成功",
  "data": null
}
```

---

### 7. 切换闹钟状态

**描述**: 启用或禁用指定闹钟。

- **方法**: `PATCH`
- **路径**: `/api/alarms/{alarm_id}/toggle`
- **请求体**:
```json
{
  "is_enabled": false
}
```

**响应示例**:
```json
{
  "success": true,
  "message": "闹钟已禁用",
  "data": null
}
```

---

## 错误处理

所有错误响应格式：

```json
{
  "success": false,
  "message": "错误信息",
  "data": null
}
```

常见状态码：
- `200`: 请求成功
- `201`: 创建成功
- `400`: 请求参数错误
- `404`: 资源不存在
- `500`: 服务器内部错误

## 测试示例

使用 curl 测试 API：

```bash
# 创建闹钟
curl -X POST http://localhost:5000/api/alarms \
  -H "Content-Type: application/json" \
  -d '{
    "alarm_id": "550e8400-e29b-41d4-a716-446655440004",
    "user_id": "user_001",
    "alarm_time": "07:30",
    "alarm_name": "早晨闹钟",
    "ai_persona_id": "gentle",
    "repeat_days": "1,2,3,4,5"
  }'

# 获取所有闹钟
curl http://localhost:5000/api/alarms

# 获取指定用户的闹钟
curl "http://localhost:5000/api/alarms?user_id=user_001"

# 更新闹钟
curl -X PUT http://localhost:5000/api/alarms/550e8400-e29b-41d4-a716-446655440001 \
  -H "Content-Type: application/json" \
  -d '{
    "alarm_id": "550e8400-e29b-41d4-a716-446655440001",
    "user_id": "user_001",
    "alarm_time": "08:00",
    "alarm_name": "更新后的闹钟",
    "ai_persona_id": "informative"
  }'

# 删除闹钟
curl -X DELETE http://localhost:5000/api/alarms/550e8400-e29b-41d4-a716-446655440001
```

## 注意事项

1. 确保 MySQL 服务已启动
2. 数据库编码使用 UTF-8
3. 生产环境请修改 `.env` 中的 `SECRET_KEY`
4. 生产环境建议设置 `DEBUG=False`

## 使用 Docker 部署（示例）

以下内容假设你的 MySQL 已经以 Docker 容器形式运行并且数据库已初始化。

1) 构建镜像并运行（使用已存在的 MySQL 容器）

 - 确保 `.env` 中的 DB_HOST 指向 MySQL 容器的主机名或容器名（例如 mysql-container），并且 MySQL 容器和本服务位于同一 Docker 网络。

  示例：创建 network 并将 MySQL 容器加入：

  ```powershell
  docker network create callclock-net
  docker network connect callclock-net <your-mysql-container-name>
  ```

  然后在 `server` 目录下构建并运行服务：

  ```powershell
  cd server
  docker build -t call-clock-server:latest .
  docker run -d --name call-clock-server --network baota_net -p 5000:5000 --env-file .env call-clock-server:latest
  ```

2) 使用 docker-compose（更多可配置项）

 - 我们在仓库提供了 `docker-compose.yml` 示例。该示例假设你已经有一个外部网络 `callclock-net` 并已将 MySQL 容器加入该网络。

  在 `server` 目录运行：

  ```powershell
  docker compose up -d --build
  ```

说明：
- 如果你愿意也可以在 `docker-compose.yml` 中直接添加 MySQL 服务块来一键启动数据库和应用（示例改动我可以帮你加）。


## License

MIT
