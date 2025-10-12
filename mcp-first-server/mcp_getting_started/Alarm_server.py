"""
闹钟 MCP 服务器
提供创建、查询、更新和删除闹钟的功能
通过 HTTP 请求调用远程闹钟服务 API
"""
import requests
from datetime import datetime
from typing import Optional
from mcp.server.fastmcp import FastMCP

# 远程闹钟服务 API 基础 URL (仅支持 HTTPS)
API_BASE_URL = "https://alarm.name666.top"

# 请求配置
REQUEST_TIMEOUT = 30  # 增加超时时间到 30 秒
MAX_RETRIES = 3  # 最大重试次数

# 创建 MCP 服务器实例
mcp = FastMCP("Alarm Manager")

# 配置请求会话,启用连接池和重试
session = requests.Session()
adapter = requests.adapters.HTTPAdapter(
    max_retries=requests.adapters.Retry(
        total=MAX_RETRIES,
        backoff_factor=1,
        status_forcelist=[500, 502, 503, 504]
    )
)
session.mount('https://', adapter)


@mcp.tool()
def create_alarm(
    alarm_id: str,
    user_id: str,
    alarm_time: str,
    alarm_name: str = "新闹钟",
    ai_persona_id: str = "gentle",
    repeat_days: Optional[str] = None,
    is_enabled: bool = True
) -> str:
    """
    创建一个新闹钟
    
    Args:
        alarm_id: 闹钟的唯一标识符
        user_id: 用户ID
        alarm_time: 闹钟时间 (格式: HH:MM，例如 "08:00")
        alarm_name: 闹钟名称（默认为"新闹钟"）
        ai_persona_id: AI人设ID，可选值: gentle(温柔), energetic(活力), informative(资讯), humorous(幽默), strict(严厉)，默认为gentle
        repeat_days: 重复日期，逗号分隔的数字字符串，1-7代表周一到周日，例如 "1,2,3,4,5" 表示工作日。留空表示一次性闹钟
        is_enabled: 是否启用闹钟（默认为True）
    
    Returns:
        创建成功的消息，包含闹钟ID
    """
    try:
        # 验证 ai_persona_id
        valid_personas = ['gentle', 'energetic', 'informative', 'humorous', 'strict']
        if ai_persona_id not in valid_personas:
            return f"错误：ai_persona_id 必须是以下之一: {', '.join(valid_personas)}"
        
        # 验证时间格式
        try:
            hour, minute = map(int, alarm_time.split(':'))
            if not (0 <= hour < 24 and 0 <= minute < 60):
                return "错误：时间格式无效，小时应在0-23之间，分钟应在0-59之间"
        except ValueError:
            return "错误：时间格式应为 HH:MM，例如 '08:00'"
        
        # 验证 repeat_days 格式
        if repeat_days:
            try:
                days = [int(d.strip()) for d in repeat_days.split(',')]
                if not all(1 <= d <= 7 for d in days):
                    return "错误：repeat_days 应包含1-7之间的数字，用逗号分隔"
            except ValueError:
                return "错误：repeat_days 格式无效，应为逗号分隔的数字，如 '1,2,3,4,5'"
        
        # 准备请求数据
        payload = {
            "alarm_id": alarm_id,
            "user_id": user_id,
            "alarm_time": alarm_time,
            "alarm_name": alarm_name,
            "ai_persona_id": ai_persona_id,
            "repeat_days": repeat_days,
            "is_enabled": is_enabled
        }
        
        # 发送 POST 请求到远程服务器 (HTTPS only)
        response = session.post(
            f"{API_BASE_URL}/api/alarms",
            json=payload,
            timeout=REQUEST_TIMEOUT,
            verify=True  # 验证 SSL 证书
        )
        
        # 检查响应
        if response.status_code == 200:
            result = response.json()
            if result.get('success'):
                # 构造返回信息
                repeat_info = ""
                if repeat_days:
                    day_names = {
                        '1': '周一', '2': '周二', '3': '周三', 
                        '4': '周四', '5': '周五', '6': '周六', '7': '周日'
                    }
                    days_list = [day_names[d.strip()] for d in repeat_days.split(',')]
                    repeat_info = f"，重复日期: {', '.join(days_list)}"
                else:
                    repeat_info = "，一次性闹钟"
                
                persona_names = {
                    'gentle': '温柔',
                    'energetic': '活力',
                    'informative': '资讯',
                    'humorous': '幽默',
                    'strict': '严厉'
                }
                
                return f"""✅ 闹钟创建成功！
📋 详细信息：
  - 闹钟ID: {alarm_id}
  - 名称: {alarm_name}
  - 时间: {alarm_time}
  - AI人设: {persona_names.get(ai_persona_id, ai_persona_id)}
  - 状态: {'已启用' if is_enabled else '已禁用'}{repeat_info}"""
            else:
                return f"❌ 创建闹钟失败：{result.get('message', '未知错误')}"
        else:
            return f"❌ 创建闹钟失败：HTTP {response.status_code} - {response.text}"
    
    except requests.exceptions.RequestException as e:
        return f"❌ 网络请求失败：{str(e)}"
    except Exception as e:
        return f"❌ 创建闹钟失败：{str(e)}"


@mcp.tool()
def get_alarm(alarm_id: str) -> str:
    """
    根据ID获取闹钟详情
    
    Args:
        alarm_id: 闹钟的唯一标识符
    
    Returns:
        闹钟详细信息或错误消息
    """
    try:
        response = session.get(
            f"{API_BASE_URL}/api/alarms/{alarm_id}",
            timeout=REQUEST_TIMEOUT,
            verify=True
        )
        
        if response.status_code == 200:
            result = response.json()
            if result.get('success'):
                alarm = result.get('data')
                
                repeat_info = ""
                if alarm.get('repeat_days'):
                    day_names = {
                        '1': '周一', '2': '周二', '3': '周三', 
                        '4': '周四', '5': '周五', '6': '周六', '7': '周日'
                    }
                    days_list = [day_names[d.strip()] for d in alarm['repeat_days'].split(',')]
                    repeat_info = f"\n  - 重复: {', '.join(days_list)}"
                else:
                    repeat_info = "\n  - 类型: 一次性闹钟"
                
                persona_names = {
                    'gentle': '温柔',
                    'energetic': '活力',
                    'informative': '资讯',
                    'humorous': '幽默',
                    'strict': '严厉'
                }
                
                return f"""📋 闹钟详情：
  - ID: {alarm.get('alarm_id')}
  - 名称: {alarm.get('alarm_name')}
  - 时间: {alarm.get('alarm_time')}
  - 用户ID: {alarm.get('user_id')}
  - AI人设: {persona_names.get(alarm.get('ai_persona_id'), alarm.get('ai_persona_id'))}
  - 状态: {'✅ 已启用' if alarm.get('is_enabled') else '❌ 已禁用'}{repeat_info}
  - 创建时间: {alarm.get('created_at', '未知')}"""
            else:
                return f"❌ {result.get('message', '未找到闹钟')}"
        elif response.status_code == 404:
            return f"❌ 未找到ID为 {alarm_id} 的闹钟"
        else:
            return f"❌ 获取闹钟失败：HTTP {response.status_code}"
    
    except requests.exceptions.RequestException as e:
        return f"❌ 网络请求失败：{str(e)}"
    except Exception as e:
        return f"❌ 获取闹钟失败：{str(e)}"


@mcp.tool()
def list_alarms(user_id: str) -> str:
    """
    获取指定用户的所有闹钟列表
    
    Args:
        user_id: 用户ID
    
    Returns:
        闹钟列表或错误消息
    """
    try:
        response = session.get(
            f"{API_BASE_URL}/api/alarms/user/{user_id}",
            timeout=REQUEST_TIMEOUT,
            verify=True
        )
        
        if response.status_code == 200:
            result = response.json()
            if result.get('success'):
                alarms = result.get('data', [])
                
                if not alarms:
                    return f"📭 用户 {user_id} 还没有创建任何闹钟"
                
                alarm_list = f"📋 用户 {user_id} 的闹钟列表（共 {len(alarms)} 个）：\n\n"
                
                for i, alarm in enumerate(alarms, 1):
                    status_icon = "✅" if alarm.get('is_enabled') else "❌"
                    repeat_mark = "🔁" if alarm.get('repeat_days') else "1️⃣"
                    alarm_list += f"{i}. {status_icon} {repeat_mark} {alarm.get('alarm_name')} - {alarm.get('alarm_time')} (ID: {alarm.get('alarm_id')})\n"
                
                return alarm_list
            else:
                return f"❌ {result.get('message', '获取闹钟列表失败')}"
        else:
            return f"❌ 获取闹钟列表失败：HTTP {response.status_code}"
    
    except requests.exceptions.RequestException as e:
        return f"❌ 网络请求失败：{str(e)}"
    except Exception as e:
        return f"❌ 获取闹钟列表失败：{str(e)}"


@mcp.tool()
def update_alarm(
    alarm_id: str,
    alarm_time: Optional[str] = None,
    alarm_name: Optional[str] = None,
    ai_persona_id: Optional[str] = None,
    repeat_days: Optional[str] = None,
    is_enabled: Optional[bool] = None
) -> str:
    """
    更新现有闹钟
    
    Args:
        alarm_id: 闹钟ID
        alarm_time: 新的闹钟时间（可选）
        alarm_name: 新的闹钟名称（可选）
        ai_persona_id: 新的AI人设ID（可选）
        repeat_days: 新的重复日期（可选）
        is_enabled: 是否启用（可选）
    
    Returns:
        更新成功的消息
    """
    try:
        if alarm_time:
            try:
                hour, minute = map(int, alarm_time.split(':'))
                if not (0 <= hour < 24 and 0 <= minute < 60):
                    return "错误：时间格式无效"
            except ValueError:
                return "错误：时间格式应为 HH:MM"
        
        if ai_persona_id:
            valid_personas = ['gentle', 'energetic', 'informative', 'humorous', 'strict']
            if ai_persona_id not in valid_personas:
                return f"错误：ai_persona_id 必须是以下之一: {', '.join(valid_personas)}"
        
        if repeat_days:
            try:
                days = [int(d.strip()) for d in repeat_days.split(',')]
                if not all(1 <= d <= 7 for d in days):
                    return "错误：repeat_days 应包含1-7之间的数字"
            except ValueError:
                return "错误：repeat_days 格式无效"
        
        payload = {}
        if alarm_time is not None:
            payload['alarm_time'] = alarm_time
        if alarm_name is not None:
            payload['alarm_name'] = alarm_name
        if ai_persona_id is not None:
            payload['ai_persona_id'] = ai_persona_id
        if repeat_days is not None:
            payload['repeat_days'] = repeat_days
        if is_enabled is not None:
            payload['is_enabled'] = is_enabled
        
        if not payload:
            return "❌ 没有提供任何要更新的字段"
        
        response = session.put(
            f"{API_BASE_URL}/api/alarms/{alarm_id}",
            json=payload,
            timeout=REQUEST_TIMEOUT,
            verify=True
        )
        
        if response.status_code == 200:
            result = response.json()
            if result.get('success'):
                return f"✅ 闹钟 {alarm_id} 更新成功！"
            else:
                return f"❌ {result.get('message', '更新闹钟失败')}"
        elif response.status_code == 404:
            return f"❌ 未找到ID为 {alarm_id} 的闹钟"
        else:
            return f"❌ 更新闹钟失败：HTTP {response.status_code}"
    
    except requests.exceptions.RequestException as e:
        return f"❌ 网络请求失败：{str(e)}"
    except Exception as e:
        return f"❌ 更新闹钟失败：{str(e)}"


@mcp.tool()
def delete_alarm(alarm_id: str) -> str:
    """
    删除指定的闹钟
    
    Args:
        alarm_id: 要删除的闹钟ID
    
    Returns:
        删除成功的消息
    """
    try:
        response = session.delete(
            f"{API_BASE_URL}/api/alarms/{alarm_id}",
            timeout=REQUEST_TIMEOUT,
            verify=True
        )
        
        if response.status_code == 200:
            result = response.json()
            if result.get('success'):
                return f"✅ 闹钟 {alarm_id} 已成功删除"
            else:
                return f"❌ {result.get('message', '删除闹钟失败')}"
        elif response.status_code == 404:
            return f"❌ 未找到ID为 {alarm_id} 的闹钟"
        else:
            return f"❌ 删除闹钟失败：HTTP {response.status_code}"
    
    except requests.exceptions.RequestException as e:
        return f"❌ 网络请求失败：{str(e)}"
    except Exception as e:
        return f"❌ 删除闹钟失败：{str(e)}"


if __name__ == "__main__":
    mcp.run()