## res://resource/core/combat/status_effect_data.gd
## 状态效果定义资源类
## 策划配置专用：用于定义游戏内的各种 Buff/Debuff 客观物理规律与触发机制。
extends Resource
class_name StatusEffectData

# ==========================================
# 核心枚举定义 (Enums)
# ==========================================

## 基础类型
enum BaseType {
	BASE,  ## 最基础的类型
	AURA,  ## 复合光环的类型
}

## 状态异常类型的总枚举
enum EffectType {
	NONE,
	# ==============================
	# 1. 通用属性修饰 (万能面板调节器)
	# ==============================
	STAT_MODIFIER,
	# ==============================
	# 2. 控制类 (CC - 剥夺敌方行动或索敌能力)
	# ==============================
	STUN,
	FREEZE,
	TAUNT,  ## 强制目标在攻击时，只能将施加者作为第一目标。
	# ==============================
	# 3. 持续伤害类 (DoT - 会造成周期性扣血)
	# ==============================
	BLEED,
	POISON,
	BURN,
	POISON_SEED,  ## 潜伏的毒素，可用于“受击叠加”、“死亡传染”或“条件引爆”机制。
	# ==============================
	# 4. 减益类 (Debuff - 削弱敌方属性或增加受击代价)
	# ==============================
	VULNERABLE,
	WEAK,
	ARMOR_BREAK,
	# ==============================
	# 5. 增益类 (Buff - 强化自身生存、反制或输出能力)
	# ==============================
	REGEN,
	SHIELD,
	ATK_UP,
	COUNTER,  ## 反击姿态。用于UI专属图标展示，并配合底层 ON_BLOCK_SUCCESS 等事件使用。
	DEFLECT,  ## 偏转护体。用于抵挡并反伤，通常配合 consume_stack_on_trigger (消耗层数) 使用。
}

## Buff的类型，无、增益、减益
enum BuffType {
	NONE,  ## 无类型
	BUFF,  ## 增益buff
	DEBUFF,  ## 减益debuff
}

## 属性修饰类型 (固定值还是百分比)
enum ModifierType {
	NONE,  ## 无
	FLAT,  ## 数值类型
	PERCENTAGE,  ## 百分比类型
}

## 状态效果造成的伤害类型
enum DamageType {
	PHYSICAL,  ## 物理伤害（参与减伤公式）
	PIERCING,  ## 穿透伤害（不参与减伤公式，但是优先扣除白盾）
	TRUE_DAMAGE,  ## 真实伤害（无视减伤，无视白盾，直接扣除真实血量）
}

## 动态数值基准引用 (计算百分比伤害/护盾时，到底乘谁的属性？)
enum ScalingReference {
	NONE,  ## 无引用 (纯固定数值)
	ATTACKER_ATK,  ## 取决于攻击者的真实攻击力
	TARGET_MAX_HP,  ## 取决于目标的生命上限
	TARGET_CURRENT_ARMOR,  ## 取决于目标的当前护甲
	TARGET_MISSING_HP,  ## 取决于目标的“已损失生命值”！(用于绝境盾、斩杀伤害)
	TARGET_MISSING_HP_PCT,  ## 目标的“已损失生命百分比”！(小数 0.0~1.0，用于阶梯运算)
	SELF_ATK,  ## 取决于光环拥有者/Buff持有者自身的攻击力！(专用于主动反击)
	INCOMING_DAMAGE,  ## 取决于本次受击的实际扣血/破盾量！(专用于真实比例反伤)
}

## 状态效果的被动触发事件池
enum TriggerEvent {
	NONE,  ## 无事件
	ON_HIT_RECEIVED,  ## 当受到攻击时触发 (用于反伤、受击挂毒/冰冻)
	ON_ATTACK,  ## 当发起攻击时触发 (用于攻击吸血、攻击附带破甲)
	ON_DEATH,  ## 当死亡时触发 (用于亡语，比如死亡爆炸传播毒素)
	ON_ENEMY_DOT_TICK,  ## 当任意敌人受到 DoT (持续伤害) 结算时触发
	ON_STATUS_APPLIED,  ## 当自身成功给任意目标施加异常状态时触发
	ON_BLOCK_SUCCESS,  ## 当成功触发格挡判定时触发！(专用于防守反击)
	ON_KILL,  ## 当宿主成功击杀任意目标时触发！(专用于被动击杀奖励)
}

## 触发目标 (反击给谁？或者死亡时炸给谁？)
enum TriggerTarget {
	SELF,  ## 触发给自己 (光环拥有者本身)
	ATTACKER,  ## 触发来源/攻击者 (用于反伤盾，把伤害弹回去)
	CURRENT_TARGET,  ## 当前攻击目标！(专用于 ON_ATTACK，把特效挂给正在挨打的敌人)
	ALL_ENEMIES,  ## 敌方全体
	ALL_ALLIES,  ## 己方全体
}

## 光环的动态生效条件枚举
enum ActivationCondition {
	ALWAYS,  ## 永远生效 (默认情况)
	HP_BELOW_PCT,  ## 仅在宿主血量【低于】指定百分比时生效 (如狂暴)
	HP_ABOVE_PCT,  ## 仅在宿主血量【高于】指定百分比时生效 (如满血增伤)
	HAS_ANY_BUFF_IN_LIST,  ## 仅在宿主带有指定数组中的【任意】异常状态时才生效！
	TARGET_HAS_ANY_BUFF_IN_LIST,  ## 仅在【当前受击目标】带有指定异常时生效！(专为破冰/趁火打劫准备)
	RESOURCE_ABOVE_PCT,  ## 宿主的特定资源(怒气/架势)比例【高于】阈值时生效
	RESOURCE_BELOW_PCT,  ## 宿主的特定资源比例【低于】阈值时生效
}

## 触发时的攻击类型限制
enum ActionRequirement {
	ANY,  ## 任何攻击都可以触发（普攻 + 技能）
	BASIC_ATTACK_ONLY,  ## 仅普攻触发
	ACTIVE_SKILL_ONLY,  ## 仅主动技能触发
}

## 状态特效的视觉挂载点
enum VfxMountPoint {
	CENTER,  ## 身体中心 (如：中毒冒泡、流血飙血)
	TOP,  ## 头顶上方 (如：眩晕星星、沉默问号)
	GROUND,  ## 脚底地面 (如：冰冻冰块、回血法阵)
}

# ==========================================
# 一、 基础信息组 (Basic Info)
# ==========================================
@export_group("Basic Info")

## 状态的唯一内部ID (程序读取用，必须唯一，不能有重复)
@export var item_id: StringName = "000"

## 私有名称 (仅供编辑器和策划参考，玩家不可见)
@export var private_name: String = ""

## 游戏内实际显示给玩家看的状态名称 (如 "中毒"、"寒冰附体")
@export var nickname: String = ""

## 状态效果的详细描述文本
@export_multiline var descrip: String = ""

## 状态效果悬浮提示的动态文本格式 (预留用于格式化字符串拼接)
@export var tooltips: String = ""

## 状态效果的图标 (用于战斗 UI 状态栏展示)
@export var icon: Texture2D

## buff的基础类型
@export var base_type: BaseType = BaseType.AURA

## Buff的类型，默认无
@export var buff_type: BuffType = BuffType.NONE

# ==========================================
# 💡 视觉与特效组 (Visual & VFX)
# ==========================================
@export_group("Visual & VFX")

## 特效在目标身上的挂载位置 (严格对应 CombatVisual 的 3 个 Marker2D)
@export var vfx_mount_point: VfxMountPoint = VfxMountPoint.CENTER

## 1. 复杂特效场景 (优先级更高)
## 用于需要粒子系统 (GPUParticles2D) 或多节点复合动画的高级 Buff (如：魔法护盾、雷暴)
@export var vfx_scene: PackedScene

## 2. 简单特效序列帧贴图 (轻量级备选)
## 用于简单的序列帧播放 (如：头顶冒金星)。【注意：如果配置了 vfx_scene，此项将被系统忽略】
@export var vfx_sheet: Texture2D

## 状态生效时附带的持续音效 (如：冰冻的结冰声、燃烧的噼啪声)
@export var loop_sound: AudioStream

# ==========================================
# 二、 状态与层数规则 (Type & Stacking)
# ==========================================
@export_group("Type & Stacking")

## 状态效果大类 (如：POISON, SHIELD 等)
@export var effect_type: EffectType = EffectType.NONE

## 最大可叠加层数 (例如中毒填 99 层，眩晕填 1 层)
@export var max_stacks: int = 1

## 叠加时的行为：当该状态已存在并再次被挂载时，是否刷新其持续时间？
@export var refresh_duration_on_stack: bool = true

## 每回合结束时自动衰减的层数
## (例如：中毒/流血填 1，代表每回合结束自动-1层；护盾/眩晕填 0，不掉层只掉持续回合)
@export var stack_decay_per_turn: int = 0

# ==========================================
# UI 表现与反馈 (UI Presentation)
# ==========================================
@export_group("UI Presentation (界面表现)")
## 是否在最后一回合持续闪烁警告。
## 建议：常规的增益/减益/持续伤害请保持开启；眩晕、冰冻等【硬控】请关闭，避免视觉噪音。
@export var enable_expire_flash: bool = true

# ==========================================
# 三、 数值与属性修饰组 (Value & Modifier)
# ==========================================
@export_group("Modifier Settings")

## 修改的目标属性名称 (仅 EffectType.STAT_MODIFIER 时有效，填写对应玩家/敌人的属性变量名)
@export var target_attribute: String = ""

## 数值修饰类型 (NONE 无 / FLAT 固定加减法 / PERCENTAGE 百分比乘法)
@export var modifier_type: ModifierType = ModifierType.NONE

## 基础效用值 (每层造成的伤害值，或者每层增加的属性值)
@export var strength_value: float = 0.0

## 动态数值引用 (如：希望流血伤害与攻击者面板挂钩，则选 ATTACKER_ATK。固定伤害则选 NONE)
@export var scaling_reference: ScalingReference = ScalingReference.NONE

## 伤害结算类型 (仅对 DoT 等能造成扣血的伤害有效，决定是否无视护甲)
@export var damage_type: DamageType = DamageType.PHYSICAL

## 组合稀有度增幅开关 (是否允许图腾综合等级影响该状态的效用值？)
@export var scale_with_skill_level: bool = false

# ==========================================
# 四、 抗性衰减机制 (Resistance Mechanics)
# ==========================================
@export_group("Resistance Mechanics")

## 每次触发后，目标临时增加的抗性 (例如：冰冻填 0.5 即目标被冻一次后增加 50% 冰冻抗性，防止无限控)
@export var resist_increase: float = 0.0

## 每回合自然衰减的抗性 (例如：填 0.5 即每回合目标积攒的抗性会自然下降 50%)
@export var resist_decay_per_turn: float = 0.0

# ==========================================
# 五、 事件触发器 (Event Triggers - 反应类机制)
# ==========================================
@export_group("Event Triggers (Reactive Mechanics)")

## 触发条件大类 (如：受击时 ON_HIT_RECEIVED，死亡时 ON_DEATH，敌人受伤时 ON_ENEMY_DOT_TICK)
@export var trigger_event: TriggerEvent = TriggerEvent.NONE

## 触发效果的目标对象 (反击给谁？或者死亡时扩散给谁？)
@export var trigger_target: TriggerTarget = TriggerTarget.ATTACKER

## 触发限制：仅在特定攻击类型时生效
@export var trigger_action_requirement: ActionRequirement = ActionRequirement.BASIC_ATTACK_ONLY

## 是否在成功触发该事件后，自动消耗/扣除 1 层该状态？
## (🔑核心机制！开启后，该状态就变成了“次数型”Buff。例如“下 1 次攻击”、“抵挡下 2 次伤害”)
@export var consume_stack_on_trigger: bool = false

# --- 触发条件过滤 ---
## 触发过滤：只有当目标受到以下特定状态的影响时才触发 (为空则不限制)
## (例如：填入 POISON 和 BLEED，则代表只有在监听中毒或流血伤害时，本触发器才生效)
@export var trigger_required_effects: Array[EffectType] = []

# --- 固定的触发效果 (常规的反伤/挂异常) ---
## 触发时，造成的伤害基准属性引用 (如反弹自身的攻击力)
@export var trigger_scaling_stat: ScalingReference = ScalingReference.NONE

## 触发时，造成的额外伤害倍率 (如 0.5 即为 50% 的伤害倍率)
@export var trigger_damage_multiplier: float = 0.0

## 动态放大的区间步长！
## (例如：填 0.15，代表基准每达到 15%，就把资源收益增加 1 倍)
@export var trigger_resource_scaling_step: float = 0.0

## 触发时，造成的伤害类型 (通常反伤盾推荐用 PIERCING 穿透或 TRUE_DAMAGE 真实伤害)
@export var trigger_damage_type: DamageType = DamageType.PHYSICAL

## 触发时，额外附加给目标的状态效果
## (拖入已配置好的 SkillEffectApplyParams 资源，如：受击时 33% 概率挂冰冻)
@export var trigger_apply_effect: SkillEffectApplyParams

# --- 触发时的资源收益 ---
## 触发时，给带有此 Buff 的单位带来的资源交易/回复！
## (拖入 SkillResourceChange 资源，例如：每次触发，自身恢复 2 点怒气)
@export var trigger_resource_changes: Array[SkillResourceChange] = []

# --- 动态传染机制 (专门为【腐败之种】亡语传染等技能准备) ---
@export_subgroup("Contagion Mechanics (传染机制)")

## 死亡/触发时，需要扩散的异常状态类型 (选 NONE 代表不使用传染机制)
@export var trigger_spread_effect: EffectType = EffectType.NONE

## 扩散层数比例 (例如填 0.5，代表将自身目前该状态总层数的 50% 传染出去)
@export var trigger_spread_ratio: float = 0.0

@export_subgroup("Dynamic Activation (动态生效条件)")
@export var activation_condition: ActivationCondition = ActivationCondition.ALWAYS
## 当条件选为 RESOURCE_ABOVE/BELOW_PCT 时，指定要监控的资源类型
@export var activation_condition_resource: SkillResourceChange.StatType = SkillResourceChange.StatType.POSTURE
@export var activation_condition_value: float = 0.0

## 当条件选为 HAS_ANY_BUFF_IN_LIST 时，用于判定生效的状态列表
## (例如：里面填入 FREEZE 和 STUN，只要宿主中了其中任意一个，光环就瞬间点亮)
@export var activation_condition_buffs: Array[EffectType] = []


# ==========================================
# 国际化与文本处理
# ==========================================
func get_translated_name() -> String:
	return tr(nickname)


func get_translated_desp() -> String:
	return tr(descrip)


func formatter_tooltip() -> void:
	push_warning("[Override this function] [%s] format the tooltip text" % item_id)
