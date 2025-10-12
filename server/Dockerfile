FROM python:3.11-slim

# 不生成 .pyc，关闭缓冲输出，便于日志实时查看
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# 先拷贝依赖清单并安装，利用缓存加速镜像构建
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# 复制项目代码
COPY . .

EXPOSE 5000

CMD ["python", "app.py"]
