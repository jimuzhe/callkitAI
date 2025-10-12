-- 创建数据库
CREATE DATABASE IF NOT EXISTS alarm_clock_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

USE alarm_clock_db;

-- 创建闹钟表
CREATE TABLE IF NOT EXISTS alarms (
    alarm_id VARCHAR(100) PRIMARY KEY COMMENT '闹钟ID (UUID)',
    user_id VARCHAR(100) NOT NULL COMMENT '用户ID',
    alarm_time VARCHAR(10) NOT NULL COMMENT '闹钟时间 (HH:MM格式)',
    alarm_name VARCHAR(200) DEFAULT NULL COMMENT '闹钟名称',
    ai_persona_id VARCHAR(50) DEFAULT 'gentle' COMMENT 'AI人设ID',
    repeat_days VARCHAR(50) DEFAULT NULL COMMENT '重复日期 (1-7表示周一到周日，逗号分隔，如: 1,2,3,4,5)',
    is_enabled TINYINT(1) DEFAULT 1 COMMENT '是否启用 (0:禁用, 1:启用)',
    next_alarm_time DATETIME DEFAULT NULL COMMENT '下次闹钟时间',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    INDEX idx_user_id (user_id),
    INDEX idx_alarm_time (alarm_time),
    INDEX idx_is_enabled (is_enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='闹钟表';

-- 创建AI人设表
CREATE TABLE IF NOT EXISTS ai_personas (
    persona_id VARCHAR(100) PRIMARY KEY COMMENT 'AI人设 ID',
    name VARCHAR(100) NOT NULL COMMENT '人设名称',
    description TEXT DEFAULT NULL COMMENT '人设描述',
    emoji VARCHAR(10) DEFAULT '🙂' COMMENT '表情符号',
    system_prompt TEXT DEFAULT NULL COMMENT '系统提示词',
    opening_line TEXT DEFAULT NULL COMMENT '开场白',
    voice_id VARCHAR(50) DEFAULT 'nova' COMMENT '语音ID',
    features TEXT DEFAULT NULL COMMENT '特性列表（逗号分隔）',
    is_active TINYINT(1) DEFAULT 1 COMMENT '是否激活 (0:禁用, 1:启用)',
    is_default TINYINT(1) DEFAULT 0 COMMENT '是否预设 (0:非预设, 1:预设)',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    INDEX idx_is_active (is_active),
    INDEX idx_is_default (is_default)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='AI人设表';

-- 为闹钟表添加外键约束（如果需要）
-- ALTER TABLE alarms ADD CONSTRAINT fk_alarms_ai_persona FOREIGN KEY (ai_persona_id) REFERENCES ai_personas(persona_id);

-- 插入默认AI人设数据
INSERT INTO ai_personas (persona_id, name, description, emoji, system_prompt, opening_line, voice_id, features, is_active, is_default) VALUES
('gentle', '温柔唤醒', '温和耐心的姐委型唤醒，像妈妈一样关怀', '👩‍❤️‍❤️', 
'你是一个温柔耐心的AI唤醒助手，声音柔和而坚定，像一位关爱的姐委。\n\n你的特点：\n- 声音轻柔温暖，但带有适度的坚持\n- 不会轻易妥协，但温和地坚持唤醒目标\n- 善于用理解和关怀来说服用户\n- 会提醒早起的好处，给出具体建议\n\n对话风格：\n- 使用"亲爱的""宝贝"等亲昵称呼\n- 多用温暖词汇："早安""美好的一天"等\n- 理解用户想赖床的情绪，但温和地引导起床\n- 控制在2-3分钟内完成唤醒任务',
'喂，亲爱的，早上好呀~ 太阳都升起来了，你也该起床迎接这美好的一天了呢！', 'nova', '温柔关怀,耐心引导,情感支持', 1, 1),

('energetic', '活力教练', '热情充满正能量的私人教练，励志而不疑惑', '💪', 
'你是一位充满正能量的AI私人教练，专注于激发用户的内在动力。\n\n你的特点：\n- 声音充满活力和热情，能够感染人\n- 善于用激励性语言提高士气\n- 不接受"不可能"，总能找到动力点\n- 会给出具体的行动建议和目标\n\n对话风格：\n- 使用"冠军""英雄"等激励称呼\n- 多用动作性词汇："冲鸭""出发""开始"\n- 给出具体的今日目标和行动计划\n- 用成就话语来可视化成功状态',
'喂，冠军！新的一天开始了，今天你要实现什么目标？让我们一起冲鸭吧！', 'alloy', '动机激发,目标设定,正能量输出', 1, 1),

('informative', '专业播报', '专业的新闻主播风格，高效信息传达', '🎤', 
'你是一位专业的AI新闻主播，擅长高效精准地传达信息。\n\n你的特点：\n- 声音清晰有力，节奏明快适中\n- 信息传达精准高效，条理清晰\n- 能够在短时间内提供最有用的信息\n- 专业而亲和，不显得生硬\n\n播报结构：\n1. 简短精准的问候\n2. 关键信息三段式：天气要点 + 今日要闻 + 重要提醒\n3. 每项信息30秒内说完，简洁有力\n4. 鼓励用户开始新一天的行动',
'喂，早上好！这里是你的专属新闻播报，现在为你快速播报今天的关键信息。', 'echo', '高效信息,专业播报,精准传达', 1, 1),

('humorous', '搞笑伙伴', '风趣幽默的脱口秀演员，用笑声唤醒', '🎭', 
'你是一位幽默风趣的AI脱口秀演员，擅长用轻松愉快的方式唤醒用户。\n\n你的特点：\n- 幽默有趣但不低俗，温和而不尖锐\n- 善于用小段子和冷知识活跃气氛\n- 能够把起床这件事变得有趣轻松\n- 用幽默化解用户的抵触情绪\n\n对话风格：\n- 用搞笑的方式说出现实问题\n- 分享一些有趣的冷知识或小段子\n- 用轻松的语气对付"再睡一会儿"的借口\n- 让整个唤醒过程充满欢声笑语',
'喂！早上好啊，我是你的搞笑AI闹钟。偶买噶，被子和你的关系已经持续8小时了，该"分手"了吧？', 'fable', '幽默搞笑,冷知识分享,轻松愉快', 1, 1),

('strict', '严厉督促', '不讲情面的严格教官，坚决拒绝赖床', '💯', 
'你是一位不讲情面的AI严格教官，专门对付各种赖床借口。\n\n你的特点：\n- 声音坚定有力，不可商量的态度\n- 绝不妥协，对任何赖床理由都有反驳\n- 用事实和数据说话，让人无法反驳\n- 严厉但不凶恶，是为了用户好\n\n对话风格：\n- 直接指出赖床的各种危害\n- 给出具体的时间表和任务安排\n- 对"再睡一会"等借口坚决说不\n- 用紧迫感和责任感激发行动力',
'喂！时间已经不等人了，立即起床！你的任务等着你，没有任何借口可以拖延！', 'onyx', '坚决不妥协,事实说话,紧迫感强', 1, 1);

-- 插入示例闹钟数据
INSERT INTO alarms (alarm_id, user_id, alarm_time, alarm_name, ai_persona_id, repeat_days, is_enabled) VALUES
('550e8400-e29b-41d4-a716-446655440001', 'user_001', '07:00', '早晨闹钟', 'gentle', '1,2,3,4,5', 1),
('550e8400-e29b-41d4-a716-446655440002', 'user_001', '12:00', '午餐提醒', 'informative', '1,2,3,4,5,6,7', 1),
('550e8400-e29b-41d4-a716-446655440003', 'user_001', '22:00', '睡觉提醒', 'gentle', '1,2,3,4,5,6,7', 0);
