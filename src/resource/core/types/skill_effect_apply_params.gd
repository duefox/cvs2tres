## res://resource/core/combat/skill_effect_apply_params.gd
extends Resource
class_name SkillEffectApplyParams

## 挂载基础的 Buff 定义资源 (把定义好的 .tres 拖进这里)
@export var effect_res: StatusEffectData

## 这个技能命中时，附加几层该状态？ (例如：毒刃填 1，猛毒爆发填 3)
@export var apply_stacks: int = 1

## 该技能覆盖的状态持续回合数 (填 -1 表示永久或使用效果本身的默认时间)
@export var override_duration: int = -1

## 基础附加命中率 (1.0 代表 100% 基础概率，后续需扣除目标抗性)
@export var apply_chance: float = 1.0
