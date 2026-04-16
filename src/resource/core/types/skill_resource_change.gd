## res://resource/core/combat/skill_resource_change.gd
## 技能资源变更参数 (Skill Resource Change)
## 用于定义释放技能时的瞬时资源交易 (如：耗血、耗怒、或者回复架势)。
extends Resource
class_name SkillResourceChange

## 变更的资源类型
enum StatType {
	HP,  ## 生命值 (用于配置卖血技能或纯回血技能)
	RAGE,  ## 怒气 (常规大招消耗，或受击/普攻获取)
	POSTURE,  ## 架势 (防御/破防机制相关资源)
}

## 交易类型：是作为代价扣除，还是作为收益获得？
enum ChangeType {
	COST,  ## 消耗：释放技能前必须满足的条件，并在释放时扣除。如果数值不足，技能将无法释放。
	GAIN,  ## 获得：释放技能成功后，系统额外“白给”的资源收益。
}

## 数值计算方式
enum ValueType {
	FLAT,  ## 固定数值 (例如：填 30，就是固定 30 点怒气)
	PERCENT_MAX,  ## 最大值的百分比 (例如：填 0.1，代表最大生命值的 10%)
	PERCENT_CURRENT,  ## 当前值的百分比 (例如：填 0.5，代表当前剩余生命值的 50%，多用于按比例卖血)
	PCT_OF_SKILL_COST,  ## 动态读取本次技能消耗的百分比！(专用于能量返还)
}

# ==========================================
# 资源交易配置
# ==========================================

## 目标资源类型 (HP/怒气/架势)
@export var stat_type: StatType = StatType.RAGE

## 交易类型 (消耗 COST/收益 GAIN)
@export var change_type: ChangeType = ChangeType.COST

## 资源计算类型 (固定值/最大值百分比/当前值百分比)
@export var value_type: ValueType = ValueType.FLAT

## 资源变更的具体数值。
@export var value: float = 0.0

## 触发概率 (0.0 ~ 1.0)。
## 注意：作为 COST (消耗) 时，通常无视此概率强制为 1.0；作为 GAIN (收益) 时才会判定概率。
@export_range(0.0, 1.0) var trigger_chance: float = 1.0
