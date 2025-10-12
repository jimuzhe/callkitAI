"""
数据访问层 (DAO - Data Access Object)
"""
from typing import List, Optional
from database import Database
from models import Alarm, AIPersona


class AlarmDAO:
    """闹钟数据访问对象"""
    
    @staticmethod
    def create(alarm: Alarm) -> int:
        """
        创建新闹钟
        :param alarm: 闹钟对象
        :return: 新创建的闹钟ID
        """
        sql = """
        INSERT INTO alarms (alarm_id, user_id, alarm_time, alarm_name, ai_persona_id, 
                           repeat_days, is_enabled, next_alarm_time, created_at, updated_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW())
        """
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (
                alarm.alarm_id,
                alarm.user_id,
                alarm.alarm_time,
                alarm.alarm_name,
                alarm.ai_persona_id,
                alarm.repeat_days,
                alarm.is_enabled,
                alarm.next_alarm_time
            ))
            return alarm.alarm_id
    
    @staticmethod
    def get_by_id(alarm_id: str) -> Optional[Alarm]:
        """
        根据ID获取闹钟
        :param alarm_id: 闹钟ID
        :return: 闹钟对象或None
        """
        sql = "SELECT * FROM alarms WHERE alarm_id = %s"
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (alarm_id,))
            result = cursor.fetchone()
            return Alarm.from_dict(result) if result else None
    
    @staticmethod
    def get_by_user(user_id: str) -> List[Alarm]:
        """
        获取用户的所有闹钟
        :param user_id: 用户ID
        :return: 闹钟列表
        """
        sql = "SELECT * FROM alarms WHERE user_id = %s ORDER BY alarm_time"
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (user_id,))
            results = cursor.fetchall()
            return [Alarm.from_dict(row) for row in results]
    
    @staticmethod
    def get_all() -> List[Alarm]:
        """
        获取所有闹钟
        :return: 闹钟列表
        """
        sql = "SELECT * FROM alarms ORDER BY created_at DESC"
        with Database.get_cursor() as cursor:
            cursor.execute(sql)
            results = cursor.fetchall()
            return [Alarm.from_dict(row) for row in results]
    
    @staticmethod
    def update(alarm: Alarm) -> bool:
        """
        更新闹钟信息
        :param alarm: 闹钟对象
        :return: 是否更新成功
        """
        sql = """
        UPDATE alarms 
        SET user_id = %s, alarm_time = %s, alarm_name = %s, ai_persona_id = %s, 
            repeat_days = %s, is_enabled = %s, next_alarm_time = %s, updated_at = NOW()
        WHERE alarm_id = %s
        """
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (
                alarm.user_id,
                alarm.alarm_time,
                alarm.alarm_name,
                alarm.ai_persona_id,
                alarm.repeat_days,
                alarm.is_enabled,
                alarm.next_alarm_time,
                alarm.alarm_id
            ))
            return cursor.rowcount > 0
    
    @staticmethod
    def delete(alarm_id: str) -> bool:
        """
        删除闹钟
        :param alarm_id: 闹钟ID
        :return: 是否删除成功
        """
        sql = "DELETE FROM alarms WHERE alarm_id = %s"
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (alarm_id,))
            return cursor.rowcount > 0
    
    @staticmethod
    def toggle_status(alarm_id: str, is_enabled: bool) -> bool:
        """
        切换闹钟启用状态
        :param alarm_id: 闹钟ID
        :param is_enabled: 是否启用
        :return: 是否更新成功
        """
        sql = "UPDATE alarms SET is_enabled = %s, updated_at = NOW() WHERE alarm_id = %s"
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (is_enabled, alarm_id))
            return cursor.rowcount > 0
    
    @staticmethod
    def get_enabled_alarms() -> List[Alarm]:
        """
        获取所有启用的闹钟
        :return: 闹钟列表
        """
        sql = "SELECT * FROM alarms WHERE is_enabled = 1 ORDER BY alarm_time"
        with Database.get_cursor() as cursor:
            cursor.execute(sql)
            results = cursor.fetchall()
            return [Alarm.from_dict(row) for row in results]


class AIPersonaDAO:
    """AI人设数据访问对象"""
    
    @staticmethod
    def create(persona: AIPersona) -> str:
        """
        创建AI人设
        :param persona: AI人设对象
        :return: 新创建的人设 ID
        """
        sql = """
        INSERT INTO ai_personas (persona_id, name, description, emoji, system_prompt, 
                                opening_line, voice_id, features, is_active, is_default, created_at, updated_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW())
        """
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (
                persona.persona_id,
                persona.name,
                persona.description,
                persona.emoji,
                persona.system_prompt,
                persona.opening_line,
                persona.voice_id,
                persona.features,
                persona.is_active,
                persona.is_default
            ))
            return persona.persona_id
    
    @staticmethod
    def get_by_id(persona_id: str) -> Optional[AIPersona]:
        """
        根据ID获取AI人设
        :param persona_id: 人设 ID
        :return: AI人设对象或None
        """
        sql = "SELECT * FROM ai_personas WHERE persona_id = %s"
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (persona_id,))
            result = cursor.fetchone()
            return AIPersona.from_dict(result) if result else None
    
    @staticmethod
    def get_all(active_only: bool = True) -> List[AIPersona]:
        """
        获取所有AI人设
        :param active_only: 是否只获取激活的人设
        :return: AI人设列表
        """
        sql = "SELECT * FROM ai_personas"
        if active_only:
            sql += " WHERE is_active = 1"
        sql += " ORDER BY is_default DESC, created_at ASC"
        
        with Database.get_cursor() as cursor:
            cursor.execute(sql)
            results = cursor.fetchall()
            return [AIPersona.from_dict(row) for row in results]
    
    @staticmethod
    def get_defaults() -> List[AIPersona]:
        """
        获取默认AI人设
        :return: 默认AI人设列表
        """
        sql = "SELECT * FROM ai_personas WHERE is_default = 1 AND is_active = 1 ORDER BY created_at ASC"
        with Database.get_cursor() as cursor:
            cursor.execute(sql)
            results = cursor.fetchall()
            return [AIPersona.from_dict(row) for row in results]
    
    @staticmethod
    def update(persona: AIPersona) -> bool:
        """
        更新AI人设信息
        :param persona: AI人设对象
        :return: 是否更新成功
        """
        sql = """
        UPDATE ai_personas 
        SET name = %s, description = %s, emoji = %s, system_prompt = %s, 
            opening_line = %s, voice_id = %s, features = %s, 
            is_active = %s, is_default = %s, updated_at = NOW()
        WHERE persona_id = %s
        """
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (
                persona.name,
                persona.description,
                persona.emoji,
                persona.system_prompt,
                persona.opening_line,
                persona.voice_id,
                persona.features,
                persona.is_active,
                persona.is_default,
                persona.persona_id
            ))
            return cursor.rowcount > 0
    
    @staticmethod
    def delete(persona_id: str) -> bool:
        """
        删除AI人设
        :param persona_id: 人设 ID
        :return: 是否删除成功
        """
        sql = "DELETE FROM ai_personas WHERE persona_id = %s"
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (persona_id,))
            return cursor.rowcount > 0
    
    @staticmethod
    def toggle_status(persona_id: str, is_active: bool) -> bool:
        """
        切换AI人设激活状态
        :param persona_id: 人设 ID
        :param is_active: 是否激活
        :return: 是否更新成功
        """
        sql = "UPDATE ai_personas SET is_active = %s, updated_at = NOW() WHERE persona_id = %s"
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (is_active, persona_id))
            return cursor.rowcount > 0
    
    @staticmethod
    def search(query: str) -> List[AIPersona]:
        """
        搜索AI人设
        :param query: 搜索关键词
        :return: 匹配的AI人设列表
        """
        sql = """
        SELECT * FROM ai_personas 
        WHERE is_active = 1 AND (
            name LIKE %s OR 
            description LIKE %s OR 
            features LIKE %s
        )
        ORDER BY is_default DESC, created_at ASC
        """
        search_term = f'%{query}%'
        with Database.get_cursor() as cursor:
            cursor.execute(sql, (search_term, search_term, search_term))
            results = cursor.fetchall()
            return [AIPersona.from_dict(row) for row in results]
