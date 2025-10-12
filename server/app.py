"""
Flask REST API 服务
"""
from flask import Flask, request, jsonify
from flask_cors import CORS
from flasgger import Swagger
from config import Config
from dao import AlarmDAO, AIPersonaDAO
from models import Alarm, AIPersona
import traceback


app = Flask(__name__)
app.config.from_object(Config)
CORS(app)  # 允许跨域请求

# 初始化 Swagger
swagger = Swagger(app)


def success_response(data=None, message="操作成功", status_code=200):
    """成功响应"""
    return jsonify({
        'success': True,
        'message': message,
        'data': data
    }), status_code


def error_response(message="操作失败", status_code=400):
    """错误响应"""
    return jsonify({
        'success': False,
        'message': message,
        'data': None
    }), status_code


@app.route('/health', methods=['GET'])
def health_check():
    """
    健康检查
    ---
    tags:
      - 系统
    responses:
      200:
        description: 服务运行正常
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "服务运行正常"
            data:
              type: null
    """
    return success_response(message="服务运行正常")


@app.route('/api/alarms', methods=['POST'])
def create_alarm():
    """
    创建新闹钟
    ---
    tags:
      - 闹钟管理
    parameters:
      - in: body
        name: alarm
        description: 闹钟信息
        required: true
        schema:
          type: object
          required:
            - alarm_id
            - user_id
            - alarm_time
          properties:
            alarm_id:
              type: string
              description: 闹钟ID
              example: "alarm_001"
            user_id:
              type: string
              description: 用户ID
              example: "user_123"
            alarm_time:
              type: string
              format: date-time
              description: 闹钟时间
              example: "2024-01-01T08:00:00Z"
            label:
              type: string
              description: 闹钟标签
              example: "早上起床"
            is_enabled:
              type: boolean
              description: 是否启用
              default: true
              example: true
            repeat_days:
              type: array
              items:
                type: integer
                minimum: 0
                maximum: 6
              description: 重复日期 (0=周日, 1=周一, ..., 6=周六)
              example: [1, 2, 3, 4, 5]
            sound_uri:
              type: string
              description: 铃声URI
              example: "sounds/default.mp3"
    responses:
      201:
        description: 闹钟创建成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "闹钟创建成功"
            data:
              type: object
              properties:
                alarm_id:
                  type: string
                  example: "alarm_001"
      400:
        description: 请求参数错误
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: false
            message:
              type: string
              example: "缺少必填字段: alarm_id"
            data:
              type: null
      500:
        description: 服务器内部错误
    """
    try:
        data = request.get_json()
        
        # 验证必填字段
        required_fields = ['alarm_id', 'user_id', 'alarm_time']
        for field in required_fields:
            if field not in data:
                return error_response(f"缺少必填字段: {field}")
        
        alarm = Alarm.from_dict(data)
        alarm_id = AlarmDAO.create(alarm)
        
        return success_response(
            data={'alarm_id': alarm_id},
            message="闹钟创建成功",
            status_code=201
        )
        
    except Exception as e:
        print(f"创建闹钟错误: {traceback.format_exc()}")
        return error_response(f"创建失败: {str(e)}", 500)


@app.route('/api/alarms/<string:alarm_id>', methods=['GET'])
def get_alarm(alarm_id):
    """
    获取单个闹钟
    ---
    tags:
      - 闹钟管理
    parameters:
      - in: path
        name: alarm_id
        type: string
        required: true
        description: 闹钟ID
        example: "alarm_001"
    responses:
      200:
        description: 获取成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "操作成功"
            data:
              type: object
              properties:
                alarm_id:
                  type: string
                  example: "alarm_001"
                user_id:
                  type: string
                  example: "user_123"
                alarm_time:
                  type: string
                  format: date-time
                  example: "2024-01-01T08:00:00Z"
                label:
                  type: string
                  example: "早上起床"
                is_enabled:
                  type: boolean
                  example: true
                repeat_days:
                  type: array
                  items:
                    type: integer
                  example: [1, 2, 3, 4, 5]
                sound_uri:
                  type: string
                  example: "sounds/default.mp3"
                created_at:
                  type: string
                  format: date-time
                  example: "2024-01-01T00:00:00Z"
                updated_at:
                  type: string
                  format: date-time
                  example: "2024-01-01T00:00:00Z"
      404:
        description: 闹钟不存在
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: false
            message:
              type: string
              example: "闹钟不存在"
            data:
              type: null
      500:
        description: 服务器内部错误
    """
    try:
        alarm = AlarmDAO.get_by_id(alarm_id)
        if alarm:
            return success_response(data=alarm.to_dict())
        else:
            return error_response("闹钟不存在", 404)
    except Exception as e:
        print(f"获取闹钟错误: {traceback.format_exc()}")
        return error_response(f"获取失败: {str(e)}", 500)


@app.route('/api/alarms', methods=['GET'])
def get_alarms():
    """
    获取闹钟列表
    ---
    tags:
      - 闹钟管理
    parameters:
      - in: query
        name: user_id
        type: string
        required: false
        description: 用户ID，用于获取特定用户的闹钟
        example: "user_123"
      - in: query
        name: enabled_only
        type: boolean
        required: false
        description: 是否只获取启用的闹钟
        default: false
        example: true
    responses:
      200:
        description: 获取成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "操作成功"
            data:
              type: array
              items:
                type: object
                properties:
                  alarm_id:
                    type: string
                    example: "alarm_001"
                  user_id:
                    type: string
                    example: "user_123"
                  alarm_time:
                    type: string
                    format: date-time
                    example: "2024-01-01T08:00:00Z"
                  label:
                    type: string
                    example: "早上起床"
                  is_enabled:
                    type: boolean
                    example: true
                  repeat_days:
                    type: array
                    items:
                      type: integer
                    example: [1, 2, 3, 4, 5]
                  sound_uri:
                    type: string
                    example: "sounds/default.mp3"
                  created_at:
                    type: string
                    format: date-time
                    example: "2024-01-01T00:00:00Z"
                  updated_at:
                    type: string
                    format: date-time
                    example: "2024-01-01T00:00:00Z"
      500:
        description: 服务器内部错误
    """
    try:
        user_id = request.args.get('user_id')
        enabled_only = request.args.get('enabled_only', '0') == '1'
        
        if user_id:
            alarms = AlarmDAO.get_by_user(user_id)
        elif enabled_only:
            alarms = AlarmDAO.get_enabled_alarms()
        else:
            alarms = AlarmDAO.get_all()
        
        alarms_data = [alarm.to_dict() for alarm in alarms]
        return success_response(data=alarms_data)
        
    except Exception as e:
        print(f"获取闹钟列表错误: {traceback.format_exc()}")
        return error_response(f"获取失败: {str(e)}", 500)


@app.route('/api/alarms/<string:alarm_id>', methods=['PUT'])
def update_alarm(alarm_id):
    """
    更新闹钟
    ---
    tags:
      - 闹钟管理
    parameters:
      - in: path
        name: alarm_id
        type: string
        required: true
        description: 闹钟ID
        example: "alarm_001"
      - in: body
        name: alarm
        description: 更新的闹钟信息
        required: true
        schema:
          type: object
          properties:
            alarm_time:
              type: string
              format: date-time
              description: 闹钟时间
              example: "2024-01-01T09:00:00Z"
            label:
              type: string
              description: 闹钟标签
              example: "会议提醒"
            is_enabled:
              type: boolean
              description: 是否启用
              example: true
            repeat_days:
              type: array
              items:
                type: integer
                minimum: 0
                maximum: 6
              description: 重复日期 (0=周日, 1=周一, ..., 6=周六)
              example: [1, 2, 3, 4, 5]
            sound_uri:
              type: string
              description: 铃声URI
              example: "sounds/meeting.mp3"
    responses:
      200:
        description: 更新成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "闹钟更新成功"
            data:
              type: null
      404:
        description: 闹钟不存在
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: false
            message:
              type: string
              example: "闹钟不存在"
            data:
              type: null
      500:
        description: 服务器内部错误
    """
    try:
        data = request.get_json()
        
        # 检查闹钟是否存在
        existing_alarm = AlarmDAO.get_by_id(alarm_id)
        if not existing_alarm:
            return error_response("闹钟不存在", 404)
        
        # 更新数据
        data['alarm_id'] = alarm_id
        alarm = Alarm.from_dict(data)
        
        success = AlarmDAO.update(alarm)
        if success:
            return success_response(message="闹钟更新成功")
        else:
            return error_response("更新失败")
            
    except Exception as e:
        print(f"更新闹钟错误: {traceback.format_exc()}")
        return error_response(f"更新失败: {str(e)}", 500)


@app.route('/api/alarms/<string:alarm_id>', methods=['DELETE'])
def delete_alarm(alarm_id):
    """
    删除闹钟
    ---
    tags:
      - 闹钟管理
    parameters:
      - in: path
        name: alarm_id
        type: string
        required: true
        description: 要删除的闹钟ID
        example: "alarm_001"
    responses:
      200:
        description: 删除成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "闹钟删除成功"
            data:
              type: null
      404:
        description: 闹钟不存在
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: false
            message:
              type: string
              example: "闹钟不存在"
            data:
              type: null
      500:
        description: 服务器内部错误
    """
    try:
        success = AlarmDAO.delete(alarm_id)
        if success:
            return success_response(message="闹钟删除成功")
        else:
            return error_response("闹钟不存在", 404)
            
    except Exception as e:
        print(f"删除闹钟错误: {traceback.format_exc()}")
        return error_response(f"删除失败: {str(e)}", 500)


@app.route('/api/alarms/<string:alarm_id>/toggle', methods=['PATCH'])
def toggle_alarm(alarm_id):
    """
    切换闹钟启用状态
    ---
    tags:
      - 闹钟管理
    parameters:
      - in: path
        name: alarm_id
        type: string
        required: true
        description: 闹钟ID
        example: "alarm_001"
      - in: body
        name: status
        description: 状态信息
        required: true
        schema:
          type: object
          required:
            - is_enabled
          properties:
            is_enabled:
              type: boolean
              description: 是否启用闹钟
              example: true
    responses:
      200:
        description: 操作成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "闹钟已启用"
            data:
              type: null
      404:
        description: 闹钟不存在
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: false
            message:
              type: string
              example: "闹钟不存在"
            data:
              type: null
      500:
        description: 服务器内部错误
    """
    try:
        data = request.get_json()
        is_enabled = data.get('is_enabled', True)
        
        success = AlarmDAO.toggle_status(alarm_id, is_enabled)
        if success:
            status = "启用" if is_enabled else "禁用"
            return success_response(message=f"闹钟已{status}")
        else:
            return error_response("闹钟不存在", 404)
            
    except Exception as e:
        print(f"切换闹钟状态错误: {traceback.format_exc()}")
        return error_response(f"操作失败: {str(e)}", 500)


# ====================
# AI人设管理 API
# ====================

@app.route('/api/personas', methods=['GET'])
def get_all_personas():
    """
    获取所有AI人设
    ---
    tags:
      - AI人设管理
    parameters:
      - in: query
        name: active_only
        type: boolean
        description: 是否只获取激活的人设
        default: true
        example: true
      - in: query
        name: search
        type: string
        description: 搜索关键词
        example: "温柔"
    responses:
      200:
        description: 获取成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "操作成功"
            data:
              type: array
              items:
                type: object
                properties:
                  id:
                    type: string
                    example: "gentle"
                  name:
                    type: string
                    example: "温柔唤醒"
                  description:
                    type: string
                    example: "温和耐心的姐委型唤醒"
      500:
        description: 服务器内部错误
    """
    try:
        active_only = request.args.get('active_only', 'true').lower() == 'true'
        search_query = request.args.get('search', '').strip()
        
        if search_query:
            personas = AIPersonaDAO.search(search_query)
        else:
            personas = AIPersonaDAO.get_all(active_only=active_only)
        
        persona_list = [persona.to_dict() for persona in personas]
        return success_response(data=persona_list)
        
    except Exception as e:
        print(f"获取AI人设列表错误: {traceback.format_exc()}")
        return error_response(f"获取失败: {str(e)}", 500)


@app.route('/api/personas/<string:persona_id>', methods=['GET'])
def get_persona(persona_id):
    """
    获取单个AI人设
    ---
    tags:
      - AI人设管理
    parameters:
      - in: path
        name: persona_id
        type: string
        required: true
        description: AI人设 ID
        example: "gentle"
    responses:
      200:
        description: 获取成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "操作成功"
            data:
              type: object
              properties:
                id:
                  type: string
                  example: "gentle"
                name:
                  type: string
                  example: "温柔唤醒"
      404:
        description: AI人设不存在
      500:
        description: 服务器内部错误
    """
    try:
        persona = AIPersonaDAO.get_by_id(persona_id)
        if persona:
            return success_response(data=persona.to_dict())
        else:
            return error_response("AI人设不存在", 404)
            
    except Exception as e:
        print(f"获取AI人设错误: {traceback.format_exc()}")
        return error_response(f"获取失败: {str(e)}", 500)


@app.route('/api/personas', methods=['POST'])
def create_persona():
    """
    创建AI人设
    ---
    tags:
      - AI人设管理
    parameters:
      - in: body
        name: persona
        description: AI人设信息
        required: true
        schema:
          type: object
          required:
            - id
            - name
            - description
          properties:
            id:
              type: string
              description: AI人设 ID
              example: "custom_001"
            name:
              type: string
              description: 人设名称
              example: "自定义人设"
            description:
              type: string
              description: 人设描述
              example: "这是一个自定义的AI人设"
            emoji:
              type: string
              description: 表情符号
              example: "🙂"
            system_prompt:
              type: string
              description: 系统提示词
            opening_line:
              type: string
              description: 开场白
            voice_id:
              type: string
              description: 声音ID
              example: "nova"
            features:
              type: array
              items:
                type: string
              description: 特性列表
    responses:
      201:
        description: 创建成功
        schema:
          type: object
          properties:
            success:
              type: boolean
              example: true
            message:
              type: string
              example: "AI人设创建成功"
            data:
              type: object
              properties:
                persona_id:
                  type: string
                  example: "custom_001"
      400:
        description: 请求参数错误
      500:
        description: 服务器内部错误
    """
    try:
        data = request.get_json()
        
        # 验证必填字段
        required_fields = ['id', 'name', 'description']
        for field in required_fields:
            if field not in data:
                return error_response(f"缺少必填字段: {field}")
        
        # 检查人设 ID是否已存在
        existing = AIPersonaDAO.get_by_id(data['id'])
        if existing:
            return error_response("人设 ID已存在", 400)
        
        persona = AIPersona.from_dict(data)
        persona_id = AIPersonaDAO.create(persona)
        
        return success_response(
            data={'persona_id': persona_id},
            message="AI人设创建成功",
            status_code=201
        )
        
    except Exception as e:
        print(f"创建AI人设错误: {traceback.format_exc()}")
        return error_response(f"创建失败: {str(e)}", 500)


@app.route('/api/personas/<string:persona_id>', methods=['PUT'])
def update_persona(persona_id):
    """
    更新AI人设
    ---
    tags:
      - AI人设管理
    parameters:
      - in: path
        name: persona_id
        type: string
        required: true
        description: AI人设 ID
        example: "gentle"
      - in: body
        name: persona
        description: 更新的人设信息
        required: true
        schema:
          type: object
          properties:
            name:
              type: string
              description: 人设名称
            description:
              type: string
              description: 人设描述
            emoji:
              type: string
              description: 表情符号
            system_prompt:
              type: string
              description: 系统提示词
            opening_line:
              type: string
              description: 开场白
            voice_id:
              type: string
              description: 声音ID
            features:
              type: array
              items:
                type: string
              description: 特性列表
            is_active:
              type: boolean
              description: 是否激活
    responses:
      200:
        description: 更新成功
      404:
        description: AI人设不存在
      500:
        description: 服务器内部错误
    """
    try:
        data = request.get_json()
        
        # 检查人设是否存在
        existing_persona = AIPersonaDAO.get_by_id(persona_id)
        if not existing_persona:
            return error_response("AI人设不存在", 404)
        
        # 更新数据
        data['id'] = persona_id
        persona = AIPersona.from_dict(data)
        
        success = AIPersonaDAO.update(persona)
        if success:
            return success_response(message="AI人设更新成功")
        else:
            return error_response("更新失败")
            
    except Exception as e:
        print(f"更新AI人设错误: {traceback.format_exc()}")
        return error_response(f"更新失败: {str(e)}", 500)


@app.route('/api/personas/<string:persona_id>', methods=['DELETE'])
def delete_persona(persona_id):
    """
    删除AI人设
    ---
    tags:
      - AI人设管理
    parameters:
      - in: path
        name: persona_id
        type: string
        required: true
        description: 要删除的AI人设 ID
        example: "custom_001"
    responses:
      200:
        description: 删除成功
      404:
        description: AI人设不存在
      500:
        description: 服务器内部错误
    """
    try:
        # 防止删除默认人设
        persona = AIPersonaDAO.get_by_id(persona_id)
        if persona and persona.is_default:
            return error_response("不能删除默认AI人设", 400)
        
        success = AIPersonaDAO.delete(persona_id)
        if success:
            return success_response(message="AI人设删除成功")
        else:
            return error_response("AI人设不存在", 404)
            
    except Exception as e:
        print(f"删除AI人设错误: {traceback.format_exc()}")
        return error_response(f"删除失败: {str(e)}", 500)


@app.route('/api/personas/<string:persona_id>/toggle', methods=['PATCH'])
def toggle_persona(persona_id):
    """
    切换AI人设激活状态
    ---
    tags:
      - AI人设管理
    parameters:
      - in: path
        name: persona_id
        type: string
        required: true
        description: AI人设 ID
        example: "gentle"
      - in: body
        name: status
        description: 状态信息
        required: true
        schema:
          type: object
          required:
            - is_active
          properties:
            is_active:
              type: boolean
              description: 是否激活人设
              example: true
    responses:
      200:
        description: 操作成功
      404:
        description: AI人设不存在
      500:
        description: 服务器内部错误
    """
    try:
        data = request.get_json()
        is_active = data.get('is_active', True)
        
        success = AIPersonaDAO.toggle_status(persona_id, is_active)
        if success:
            status = "激活" if is_active else "禁用"
            return success_response(message=f"AI人设已{status}")
        else:
            return error_response("AI人设不存在", 404)
            
    except Exception as e:
        print(f"切换AI人设状态错误: {traceback.format_exc()}")
        return error_response(f"操作失败: {str(e)}", 500)


@app.errorhandler(404)
def not_found(error):
    """404错误处理"""
    return error_response("接口不存在", 404)


@app.errorhandler(500)
def internal_error(error):
    """500错误处理"""
    return error_response("服务器内部错误", 500)


if __name__ == '__main__':
    app.run(
        host=Config.HOST,
        port=Config.PORT,
        debug=Config.DEBUG
    )
