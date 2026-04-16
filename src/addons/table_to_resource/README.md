📊 TableToResource 终极配表转换插件指南
TableToResource 是一个为 Godot 4 深度定制的双向数据同步插件。它不仅能将 CSV 电子表格一键批量转换为 Godot 原生的 .tres 资源文件，还能将游戏中调整好的资源文件逆向导出为 CSV 表格。

核心优势：支持无限嵌套的子资源（套娃）、动态类名映射、智能枚举解析以及增量更新，彻底解放游戏配表工作流！

🚀 快速上手 (使用流程)
插件面板分为两个核心选项卡（Tab）：正向生成 (CSV -> Tres) 和 逆向导出 (Tres -> CSV)。

📌 预备工作：构建类名映射字典（非常重要）
如果你的配表数据中包含“内联子资源”（例如技能配置里嵌套了 SkillEffect 字典），你需要先扫描项目：

点击插件界面中的 [扫描] 按钮。

选择你存放 GDScript 数据类（.gd）的根目录。

插件会自动提取所有带有 class_name 的脚本，并在插件核心目录下生成 class_map.json 供运行时查表使用。

注：此操作通常只需在项目新增了数据结构类时执行一次，插件启动时会自动回填已保存的字典路径。

📥 1. 正向导入：将 CSV 转为 Tres
选择 CSV 表格：选择策划配置好的 .csv 文件。

选择导出文件夹：选择生成的 .tres 资源存放路径。

关联脚本：选择这些资源对应的基础数据类文件（例如 res://.../base_item_data.gd）。

唯一索引：选择 CSV 中用作文件名的列（通常是 id 或 item_id）。

执行操作：

[全量生成]：直接覆盖或新建所有资源。不在表里的属性将被重置为脚本默认值。

[批量更新]：推荐使用！ 只更新 CSV 中存在的列，保留你在 Godot 编辑器中手动微调的其他属性（增量修改）。

📤 2. 逆向导出：将 Tres 转回 CSV
当你或者策划在 Godot 编辑器（Inspector）中对资源数值进行了可视化调优，可以通过此功能同步回表格：

切入 [逆向导出] 选项卡。

选择资源目录：选择包含 .tres 文件的文件夹。

另存为 CSV：设置导出的表格路径和文件名（如 res://data/csv/items_export.csv）。

点击 [导出 CSV 表格]。插件会自动清洗底层属性，将你的枚举、套娃资源等“降维”还原为高度可读的 CSV 格式。

📝 电子表格数据填写规范 (约定优于配置)
插件采用强类型反射机制。你不需要在表头定义类型，插件会自动读取关联的 .gd 脚本中的变量类型，对 CSV 单元格内容进行强制转换。

1. 基础数据类型
数据类型,填写示例,解析说明
Int (整数),100,脚本定义为 int，填 100.5 也会被强转为 100。
Float (浮点数),1 或 1.5,填整数 1 也会被自动转换为浮点数 1.0。
String (字符串),"剑 或 ""剑""",带不带双引号皆可，插件会自动脱去外层引号。
Bool (布尔值),true 或 1,"兼容 true/false, True/False 或 1/0。"

2. Enum (枚举) ⭐️
如果脚本中的变量是枚举类型（如 export var weapon_type: WeaponType）：

写法 1（推荐）：直接写枚举的字符串 Key，如 SWORD。

写法 2：写数字，如 0 或 1。

插件通过全局常量池智能反查，确保无论填数字还是字符串，正逆向都能完美对应。

3. Array (数组)
数组必须使用 JSON 格式（包裹在 [] 中）。

字符串数组：["攻击", "防御"] 或直接写 [100] (如果目标是 Array[String]，100 会自动强转为 "100")。

数字数组：[1, 2, 3.5]

枚举数组：["SWORD", "BOW"] 或 [0, 1]。

4. Dictionary (字典) 与 Vector (向量)
字典使用 JSON 格式（包裹在 {} 中）。
为了解决 JSON 不支持 Godot 向量的痛点，我们在字典内部约定了 圆括号 () 表示向量 的特殊语法：

普通字典：{"damage": 100, "name": "毒药"}

包含向量的字典：{"down": (0, 1), "right": (1.5, 1, 0)}

(0, 1) 会被自动解析为 Vector2，(0, 0, 0) 会被解析为 Vector3。

5. 外部资源引用 (Resource Paths)
如果该字段是一个独立的外部资源（如图片、场景、其他 Tres）：

直接填写绝对路径：res://assets/icons/sword.png

6. AtlasTexture (图集切片)
如果字段类型为 AtlasTexture，可以通过特殊语法一次性赋值图片路径和裁剪区域：

格式：路径:x,y,w,h

示例：res://assets/atlas.png:0,0,64,64

7. 无限套娃子资源 (Inline SubResource) 🔥
当技能配置需要附加一个或多个私有的复杂参数时（不需要产生额外的独立文件），你可以在单元格里直接“无中生有”实例化一个对象。

语法要求：必须在 JSON 字典中包含魔法键 "class_name"。

单对象示例：
{"class_name": "StatusEffect", "duration": 5.0, "buff_type": "POISON"}

对象数组示例 (如 Array[SkillEffectApplyParams])：
[
  {"class_name": "SkillEffectApplyParams", "effect_res": "res://.../poison.tres", "chance": 0.8},
  {"class_name": "SkillEffectApplyParams", "effect_res": "res://.../stun.tres"}
]

插件会根据 class_name 在自动生成的 class_map.json 中查找到对应的脚本，并递归为其内部属性赋值！没有填写的属性将自动使用代码里的默认值。
