"""
数据模型定义
"""
from datetime import datetime
from typing import Optional, Dict, Any


class Alarm:
    """闹钟数据模型"""
    
    def __init__(
        self,
        alarm_id: Optional[str] = None,
        user_id: Optional[str] = None,
        alarm_time: Optional[str] = None,
        alarm_name: Optional[str] = None,
        ai_persona_id: Optional[str] = 'gentle',
        repeat_days: Optional[str] = None,
        is_enabled: bool = True,
        next_alarm_time: Optional[datetime] = None,
        created_at: Optional[datetime] = None,
        updated_at: Optional[datetime] = None
    ):
        self.alarm_id = alarm_id
        self.user_id = user_id
        self.alarm_time = alarm_time
        self.alarm_name = alarm_name
        self.ai_persona_id = ai_persona_id  # AI人设ID (gentle, energetic, informative, humorous, strict)
        self.repeat_days = repeat_days  # 例如: "1,2,3,4,5" 表示周一到周五
        self.is_enabled = is_enabled
        self.next_alarm_time = next_alarm_time
        self.created_at = created_at
        self.updated_at = updated_at
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            'alarm_id': self.alarm_id,
            'user_id': self.user_id,
            'alarm_time': self.alarm_time,
            'alarm_name': self.alarm_name,
            'ai_persona_id': self.ai_persona_id,
            'repeat_days': self.repeat_days,
            'is_enabled': self.is_enabled,
            'next_alarm_time': self.next_alarm_time.isoformat() if self.next_alarm_time else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'Alarm':
        """从字典创建对象"""
        return cls(
            alarm_id=data.get('alarm_id'),
            user_id=data.get('user_id'),
            alarm_time=data.get('alarm_time'),
            alarm_name=data.get('alarm_name'),
            ai_persona_id=data.get('ai_persona_id', 'gentle'),
            repeat_days=data.get('repeat_days'),
            is_enabled=data.get('is_enabled', True),
            next_alarm_time=data.get('next_alarm_time'),
            created_at=data.get('created_at'),
            updated_at=data.get('updated_at')
        )


class AIPersona:
    """AI人设数据模型"""
    
    def __init__(
        self,
        persona_id: Optional[str] = None,
        name: Optional[str] = None,
        description: Optional[str] = None,
        emoji: Optional[str] = '🙂',
        system_prompt: Optional[str] = None,
        opening_line: Optional[str] = None,
        voice_id: Optional[str] = 'nova',
        features: Optional[str] = None,
        is_active: bool = True,
        is_default: bool = False,
        created_at: Optional[datetime] = None,
        updated_at: Optional[datetime] = None
    ):
        self.persona_id = persona_id
        self.name = name
        self.description = description
        self.emoji = emoji
        self.system_prompt = system_prompt
        self.opening_line = opening_line
        self.voice_id = voice_id
        self.features = features  # 用逗号分隔的特性列表，如"温柔关怀,耐心引导,情感支持"
        self.is_active = is_active
        self.is_default = is_default
        self.created_at = created_at
        self.updated_at = updated_at
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典"""
        return {
            'id': self.persona_id,
            'name': self.name,
            'description': self.description,
            'emoji': self.emoji,
            'system_prompt': self.system_prompt,
            'opening_line': self.opening_line,
            'voice_id': self.voice_id,
            'features': self.features.split(',') if self.features else [],
            'is_active': self.is_active,
            'is_default': self.is_default,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None
        }
    
    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> 'AIPersona':
        """从字典创建对象"""
        features_list = data.get('features', [])
        features_str = ','.join(features_list) if isinstance(features_list, list) else features_list
        
        return cls(
            persona_id=data.get('id'),
            name=data.get('name'),
            description=data.get('description'),
            emoji=data.get('emoji', '🙂'),
            system_prompt=data.get('system_prompt'),
            opening_line=data.get('opening_line'),
            voice_id=data.get('voice_id', 'nova'),
            features=features_str,
            is_active=data.get('is_active', True),
            is_default=data.get('is_default', False),
            created_at=data.get('created_at'),
            updated_at=data.get('updated_at')
        )
