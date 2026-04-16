# res://addons/table_to_resource/core/table_to_resource.gd
@tool
extends RefCounted
class_name TableToResCore

## 默认的类名映射字典保存路径（和本脚本同级目录）
const DEFAULT_MAP_PATH: String = "res://addons/table_to_resource/core/class_map.json"

signal log_updated(msg: String, type: LogType)
enum LogType { INFO, SUCCESS, ERROR, WARNING }

# 运行时缓存的类名映射字典
var _current_class_map: Dictionary = {}
# 当前正在处理的脚本的枚举/常量字典，用于解决 Godot 4 吞掉 Array 枚举键的问题
var _current_script_constants: Dictionary = {}

# =========================================================
# 模块 A：扫描与构建映射字典 (Class Registry)
# =========================================================


func build_class_map(scan_dir: String, save_path: String) -> void:
	_emit_log("开始扫描目录构建类名映射: " + scan_dir, LogType.INFO)
	var class_map = {}
	_scan_dir_recursive(scan_dir, class_map)
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(class_map, "\t"))
		_emit_log("共收录 %d 个类。字典保存至: %s" % [class_map.size(), save_path], LogType.SUCCESS)
	else:
		_emit_log("保存映射字典失败: " + save_path, LogType.ERROR)


func _scan_dir_recursive(dir_path: String, map: Dictionary) -> void:
	var dir = DirAccess.open(dir_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir() and file_name not in [".", ".."]:
				_scan_dir_recursive(dir_path.path_join(file_name), map)
			elif file_name.ends_with(".gd"):
				var full_path = dir_path.path_join(file_name)
				var class_name_str = _extract_class_name(full_path)
				if not class_name_str.is_empty():
					map[class_name_str] = full_path
			file_name = dir.get_next()


func _extract_class_name(file_path: String) -> String:
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		return ""
	var regex = RegEx.new()
	regex.compile("class_name\\s+([A-Za-z0-9_]+)")
	var result = regex.search(file.get_as_text())
	return result.get_string(1) if result else ""


# =========================================================
# 模块 B：正向生成与更新 (CSV -> Tres)
# =========================================================


func get_csv_headers(csv_path: String) -> Array:
	var file = FileAccess.open(csv_path, FileAccess.READ)
	return Array(file.get_csv_line()) if file else []


func execute_conversion(csv_path: String, export_dir: String, id_field: String, target_script_path: String, class_map_path: String = "", is_update_mode: bool = false) -> void:
	if not DirAccess.dir_exists_absolute(export_dir):
		DirAccess.make_dir_recursive_absolute(export_dir)

	var TargetScript = load(target_script_path)
	if not TargetScript:
		_emit_log("无法加载目标脚本", LogType.ERROR)
		return

	# 提取主脚本的全局枚举和常量 (重要：解决枚举数组问题)
	_current_script_constants = TargetScript.get_script_constant_map()

	# 载入类名映射表
	_current_class_map.clear()
	if not class_map_path.is_empty() and FileAccess.file_exists(class_map_path):
		var json = JSON.new()
		if json.parse(FileAccess.get_file_as_string(class_map_path)) == OK and json.data is Dictionary:
			_current_class_map = json.data

	var temp_instance = TargetScript.new()
	var prop_meta_map = _get_property_meta_map(temp_instance)
	if temp_instance is Node:
		temp_instance.queue_free()

	var file = FileAccess.open(csv_path, FileAccess.READ)
	var headers = Array(file.get_csv_line())
	var id_index = headers.find(id_field)

	var sc_up = 0
	var sc_cr = 0
	_emit_log("--- 开始批量更新 ---" if is_update_mode else "--- 开始全量生成 ---", LogType.INFO)

	while !file.eof_reached():
		var row = file.get_csv_line()
		if row.size() < headers.size() or row[0].strip_edges().is_empty():
			continue

		var file_name = row[id_index].strip_edges()
		var final_path = export_dir.path_join(file_name + ".tres")
		var instance = null
		var is_new = false

		if is_update_mode and ResourceLoader.exists(final_path):
			instance = load(final_path)
		else:
			instance = TargetScript.new()
			is_new = true

		for i in range(headers.size()):
			if i >= row.size():
				break
			var raw_value = row[i].strip_edges()
			if raw_value.is_empty():
				continue

			var prop_name = headers[i].strip_edges()
			if prop_name in instance:
				var meta = prop_meta_map.get(prop_name, {})
				var t_type = meta.get("type", TYPE_NIL)
				var hint_str = meta.get("hint_string", "")
				var hint_val = meta.get("hint", 0)

				if t_type == TYPE_ARRAY:
					var exist_arr = instance.get(prop_name)
					var parsed_arr = _parse_array(raw_value, hint_str)
					if exist_arr is Array:
						exist_arr.clear()
						exist_arr.append_array(parsed_arr)
					else:
						instance.set(prop_name, parsed_arr)
				elif t_type == TYPE_DICTIONARY:
					var exist_dict = instance.get(prop_name)
					var parsed_dict = _parse_dictionary(raw_value)
					if exist_dict is Dictionary:
						exist_dict.clear()
						exist_dict.merge(parsed_dict, true)
					else:
						instance.set(prop_name, parsed_dict)
				else:
					var final_val = _force_cast_value(raw_value, t_type, hint_val, hint_str)
					if final_val != null or t_type == TYPE_OBJECT:
						instance.set(prop_name, final_val)

		if ResourceSaver.save(instance, final_path) == OK:
			if is_new:
				sc_cr += 1
			else:
				sc_up += 1

	if is_update_mode:
		_emit_log("更新完成！更新 %d 个，新建 %d 个。" % [sc_up, sc_cr], LogType.SUCCESS)
	else:
		_emit_log("生成完成！成功生成 %d 个资源。" % sc_cr, LogType.SUCCESS)


# =========================================================
# 模块 C：逆向导出 (Tres -> CSV)
# =========================================================


## 核心接口：将目录下的 Tres 逆向转换为 CSV 文件
func execute_export_to_csv(tres_dir: String, output_csv_path: String) -> void:
	if not DirAccess.dir_exists_absolute(tres_dir):
		_emit_log("资源目录不存在: " + tres_dir, LogType.ERROR)
		return

	_emit_log("--- 开始逆向导出 ---", LogType.INFO)
	var tres_files = []
	_collect_files_recursive(tres_dir, ".tres", tres_files)

	if tres_files.is_empty():
		_emit_log("目录下未找到任何 .tres 资源。", LogType.WARNING)
		return

	var all_data_rows = []
	var headers_pool = []

	for path in tres_files:
		var res = load(path)
		if not res:
			continue

		# 切换当前处理的脚本环境 (重要)
		var script = res.get_script()
		if script:
			_current_script_constants = script.get_script_constant_map()
		else:
			_current_script_constants.clear()

		var row_dict = {}

		# 必须同时包含 EDITOR(暴露在面板) 和 SCRIPT_VARIABLE(用户脚本定义)
		for p in res.get_property_list():
			if (p.usage & PROPERTY_USAGE_EDITOR) > 0 and (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) > 0:
				var prop_name = p.name
				if not prop_name in headers_pool:
					headers_pool.append(prop_name)
				# 传入 hint 和 hint_string 用于枚举还原
				row_dict[prop_name] = _serialize_for_csv(res.get(prop_name), p.hint, p.hint_string)

		# 强制注入 ID
		var default_id = path.get_file().get_basename()
		if not "item_id" in row_dict or str(row_dict.get("item_id", "")).is_empty():
			row_dict["item_id"] = default_id
			if not "item_id" in headers_pool:
				headers_pool.insert(0, "item_id")

		all_data_rows.append(row_dict)

	var file = FileAccess.open(output_csv_path, FileAccess.WRITE)
	if not file:
		_emit_log("无法创建 CSV 文件: " + output_csv_path, LogType.ERROR)
		return

	# [修复1：中文乱码] 写入 UTF-8 BOM，强制 Excel 正确识别中文编码
	file.store_string("\uFEFF")

	file.store_csv_line(PackedStringArray(headers_pool))
	for row_dict in all_data_rows:
		var line_arr = PackedStringArray()
		for h in headers_pool:
			line_arr.append(str(row_dict.get(h, "")))
		file.store_csv_line(line_arr)

	_emit_log("逆向导出完成！共导出 %d 个资源，已保存至: %s" % [all_data_rows.size(), output_csv_path], LogType.SUCCESS)


## 将任意 Godot 变量转换为适合填入 CSV 单元格的 String
func _serialize_for_csv(val, hint: int = 0, hint_string: String = "") -> String:
	match typeof(val):
		TYPE_NIL:
			return ""
		TYPE_BOOL:
			return "true" if val else "false"
		TYPE_INT:
			if hint == PROPERTY_HINT_ENUM:
				return _get_enum_string(val, hint_string)
			return str(val)
		TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return str(val)
		# 把 hint 和 hint_string 传给递归函数
		TYPE_ARRAY, TYPE_DICTIONARY:
			return JSON.stringify(_get_raw_serializable(val, hint, hint_string))
		TYPE_OBJECT:
			return _serialize_object(val)
	return str(val)


func _serialize_object(obj: Object) -> String:
	if not is_instance_valid(obj):
		return ""
	if obj is AtlasTexture:
		return "%s:%d,%d,%d,%d" % [obj.atlas.resource_path if obj.atlas else "", obj.region.position.x, obj.region.position.y, obj.region.size.x, obj.region.size.y]
	if obj is Resource:
		if not obj.resource_path.is_empty() and not obj.resource_path.contains("::"):
			return obj.resource_path
		return JSON.stringify(_get_raw_serializable(obj))
	return ""


func _get_raw_serializable(val, hint: int = 0, hint_string: String = ""):
	match typeof(val):
		# 拦截底层的 Int，如果是枚举则转为 String Key
		TYPE_INT:
			if hint == PROPERTY_HINT_ENUM:
				return _get_enum_string(val, hint_string)
			return val
		TYPE_ARRAY:
			var arr = []
			var e_hint = 0
			var e_hint_str = ""
			# 解析 Godot 4 的数组 hint，例如 "2/2:Enum1,Enum2"
			if ":" in hint_string:
				var tp = hint_string.split(":")[0]
				if "/" in tp:
					e_hint = tp.split("/")[1].to_int()
				e_hint_str = hint_string.substr(hint_string.find(":") + 1)
			for item in val:
				arr.append(_get_raw_serializable(item, e_hint, e_hint_str))
			return arr
		TYPE_DICTIONARY:
			var dict = {}
			for k in val.keys():
				dict[k] = _get_raw_serializable(val[k])
			return dict
		TYPE_OBJECT:
			if not is_instance_valid(val):
				return null
			if val is Resource:
				if not val.resource_path.is_empty() and not val.resource_path.contains("::"):
					return val.resource_path
				var dict = {}
				var script = val.get_script()

				# 压栈：保存外层常量
				var old_consts = _current_script_constants.duplicate()

				if script:
					var g_name = script.get_global_name()
					if not g_name.is_empty():
						dict["class_name"] = g_name
					else:
						dict["_script"] = script.resource_path
					# 切换至内嵌对象的常量环境
					_current_script_constants = script.get_script_constant_map()

				for p in val.get_property_list():
					if (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) > 0:
						# 向下传递内联属性的 hint 数据
						dict[p.name] = _get_raw_serializable(val.get(p.name), p.hint, p.hint_string)

				# 出栈：恢复外层常量
				_current_script_constants = old_consts
				return dict
		TYPE_VECTOR2:
			return "(%s,%s)" % [str(val.x), str(val.y)]
		TYPE_VECTOR3:
			return "(%s,%s,%s)" % [str(val.x), str(val.y), str(val.z)]
		TYPE_STRING_NAME:
			return str(val)
	return val


func _collect_files_recursive(dir_path: String, ext: String, res: Array) -> void:
	var dir = DirAccess.open(dir_path)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and file_name not in [".", ".."]:
			_collect_files_recursive(dir_path.path_join(file_name), ext, res)
		elif not dir.current_is_dir() and file_name.ends_with(ext):
			res.append(dir_path.path_join(file_name))
		file_name = dir.get_next()


# =========================================================
# 内部辅助解析器
# =========================================================


func _emit_log(msg: String, type: int):
	log_updated.emit(msg, type)


func _get_property_meta_map(obj: Object) -> Dictionary:
	var map = {}
	for p in obj.get_property_list():
		map[p.name] = {"type": p.type, "hint": p.hint, "hint_string": p.hint_string}
	return map


func _force_cast_value(val_str: String, target_type: int, hint: int, hint_string: String):
	match target_type:
		TYPE_BOOL:
			return val_str.to_lower() == "true" or val_str == "1"
		TYPE_INT:
			if hint == PROPERTY_HINT_ENUM:
				return _parse_enum(val_str, hint_string)
			return int(float(val_str))
		TYPE_FLOAT:
			return float(val_str)
		TYPE_STRING, TYPE_STRING_NAME:
			var c = val_str.strip_edges()
			if (c.begins_with('"') and c.ends_with('"')) or (c.begins_with("'") and c.ends_with("'")):
				if c.length() >= 2:
					c = c.substr(1, c.length() - 2)
			return StringName(c) if target_type == TYPE_STRING_NAME else c
		TYPE_OBJECT:
			return _parse_object(val_str)
		TYPE_DICTIONARY:
			return _parse_dictionary(val_str)
	return val_str


func _parse_dictionary(val_str: String) -> Dictionary:
	var clean = val_str.strip_edges()
	if clean.is_empty():
		return {}
	var regex = RegEx.new()
	regex.compile("\\(([\\d\\.,\\s\\-]+)\\)")
	var matches = regex.search_all(clean)
	for i in range(matches.size() - 1, -1, -1):
		var m = matches[i]
		var parts = m.get_string(1).split(",")
		var rep = ""
		if parts.size() == 2:
			rep = "Vector2(" + m.get_string(1) + ")"
		elif parts.size() == 3:
			rep = "Vector3(" + m.get_string(1) + ")"
		elif parts.size() == 4:
			rep = "Vector4(" + m.get_string(1) + ")"
		else:
			continue
		clean = clean.substr(0, m.get_start()) + rep + clean.substr(m.get_end())
	var parsed = str_to_var(clean)
	if parsed is Dictionary:
		return parsed
	var json = JSON.new()
	if json.parse(clean) == OK and json.data is Dictionary:
		return json.data
	return {}


func _parse_array(val_str: String, hint_string: String) -> Array:
	var json = JSON.new()
	var raw = json.data if json.parse(val_str) == OK and json.data is Array else _fallback_split(val_str)
	var e_type = TYPE_NIL
	var e_hint = 0
	var e_hint_str = ""

	# 提取数组内部元素的真实 hint (例如识别出这是个 Enum)
	if ":" in hint_string:
		var tp = hint_string.split(":")[0]
		if "/" in tp:
			e_type = tp.split("/")[0].to_int()
			e_hint = tp.split("/")[1].to_int()
		else:
			e_type = tp.to_int()
		e_hint_str = hint_string.substr(hint_string.find(":") + 1)

	var res = []
	for i in raw:
		res.append(_cast_single_element(i, e_type, e_hint, e_hint_str))
	return res


func _cast_single_element(item, target_type: int, hint: int = 0, hint_string: String = ""):
	if target_type == TYPE_OBJECT and typeof(item) == TYPE_DICTIONARY:
		return _dict_to_instanced_object(item)
	var s = str(item).strip_edges()
	match target_type:
		TYPE_STRING, TYPE_STRING_NAME:
			if (s.begins_with('"') and s.ends_with('"')) or (s.begins_with("'") and s.ends_with("'")):
				if s.length() >= 2:
					s = s.substr(1, s.length() - 2)
			return StringName(s) if target_type == TYPE_STRING_NAME else s
		TYPE_INT:
			# 数组/字典的内部元素支持解析 Enum 字符串 (如 "MATERIAL" -> 4)
			if hint == PROPERTY_HINT_ENUM:
				return _parse_enum(s, hint_string)
			return int(float(s))
		TYPE_FLOAT:
			return float(s)
		TYPE_BOOL:
			return s.to_lower() == "true" or s == "1"
		TYPE_OBJECT:
			return load(s) if ResourceLoader.exists(s) else null
		_:
			return load(s) if s.begins_with("res://") and ResourceLoader.exists(s) else item


func _dict_to_instanced_object(dict: Dictionary) -> Object:
	var path = ""
	if dict.has("class_name") and _current_class_map.has(dict["class_name"]):
		path = _current_class_map[dict["class_name"]]
	elif dict.has("_script"):
		path = dict["_script"]
	else:
		return null

	if not ResourceLoader.exists(path):
		return null
	var ScriptClass = load(path)
	var obj = ScriptClass.new()
	var metas = _get_property_meta_map(obj)

	# 压栈：保存外层常量，读取内层常量
	var old_consts = _current_script_constants.duplicate()
	_current_script_constants = ScriptClass.get_script_constant_map()

	for key in dict.keys():
		if key in ["class_name", "_script"]:
			continue
		if key in obj:
			var meta = metas.get(key, {})
			var t_type = meta.get("type", TYPE_NIL)
			var raw_val = dict[key]
			var final_val = null

			if t_type == TYPE_ARRAY and typeof(raw_val) == TYPE_ARRAY:
				final_val = _parse_array(JSON.stringify(raw_val), meta.get("hint_string", ""))
			elif t_type == TYPE_OBJECT and typeof(raw_val) == TYPE_DICTIONARY:
				final_val = _dict_to_instanced_object(raw_val)
			elif t_type == TYPE_DICTIONARY and typeof(raw_val) == TYPE_DICTIONARY:
				final_val = raw_val
			else:
				final_val = _force_cast_value(
					JSON.stringify(raw_val) if typeof(raw_val) in [TYPE_DICTIONARY, TYPE_ARRAY] else str(raw_val), t_type, meta.get("hint", 0), meta.get("hint_string", "")
				)
			if final_val != null or t_type == TYPE_OBJECT:
				obj.set(key, final_val)

	# 出栈：恢复外层常量
	_current_script_constants = old_consts
	return obj


func _parse_object(val_str: String):
	if val_str.contains(",") and val_str.contains(":"):
		var p = val_str.rsplit(":", true, 1)
		if p.size() == 2:
			var r = p[1].split(",")
			if r.size() == 4:
				var atlas = AtlasTexture.new()
				if ResourceLoader.exists(p[0]):
					atlas.atlas = load(p[0])
					atlas.region = Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
				return atlas
	return load(val_str) if ResourceLoader.exists(val_str) else null


func _fallback_split(val_str: String) -> Array:
	var clean = val_str.strip_edges()
	if clean.begins_with("["):
		clean = clean.substr(1)
	if clean.ends_with("]"):
		clean = clean.substr(0, clean.length() - 1)
	return clean.split(",") if not clean.is_empty() else []


func _parse_enum(val_str: String, hint_string: String) -> int:
	# 兼容处理："1" (字符串)、 1 (数字) 或是 JSON 解析出的浮点 "1.0"
	if val_str.is_valid_int():
		return val_str.to_int()
	if val_str.is_valid_float():
		return int(val_str.to_float())

	var clean = val_str.strip_edges().replace('"', "").replace("'", "")

	# 1. 尝试全局注册类的枚举 (如 "ItemLevel.WeaponType")
	if hint_string.contains("."):
		var p = hint_string.split(".")
		if _current_class_map.has(p[0]):
			var s = load(_current_class_map[p[0]])
			if s:
				var consts = s.get_script_constant_map()
				if consts.has(p[1]) and typeof(consts[p[1]]) == TYPE_DICTIONARY:
					if consts[p[1]].has(clean):
						return consts[p[1]][clean]

	# 2. 尝试在当前脚本的枚举字典中查找
	if _current_script_constants.has(hint_string) and typeof(_current_script_constants[hint_string]) == TYPE_DICTIONARY:
		if _current_script_constants[hint_string].has(clean):
			return _current_script_constants[hint_string][clean]

	# 3. 尝试在当前脚本的扁平常量池中查找
	if _current_script_constants.has(clean):
		var v = _current_script_constants[clean]
		if typeof(v) == TYPE_INT:
			return v

	# 4. 兜底方案：Godot 原生的隐式提示字符串解析 (如 "SWORD:0,BOW:1")
	var items = hint_string.split(",")
	var idx = 0
	for item in items:
		var k = item
		var v = idx
		if ":" in item:
			var pts = item.split(":")
			k = pts[0]
			v = int(pts[1])
		else:
			idx += 1
		if _fuzzy_match(clean, k):
			return v

	return 0


## 逆向解析枚举：将 Int 数字还原为配置的 String 键名
func _get_enum_string(val: int, hint_string: String) -> String:
	# 1. 尝试全局注册类的枚举
	if hint_string.contains("."):
		var p = hint_string.split(".")
		if _current_class_map.has(p[0]):
			var s = load(_current_class_map[p[0]])
			if s:
				var consts = s.get_script_constant_map()
				if consts.has(p[1]) and typeof(consts[p[1]]) == TYPE_DICTIONARY:
					for k in consts[p[1]].keys():
						if consts[p[1]][k] == val:
							return str(k)

	# 2. 尝试在当前脚本的枚举字典中查找
	if _current_script_constants.has(hint_string) and typeof(_current_script_constants[hint_string]) == TYPE_DICTIONARY:
		var d = _current_script_constants[hint_string]
		for k in d.keys():
			if d[k] == val:
				return str(k)

	# 3. 兜底方案：Godot 原生的隐式提示字符串解析
	var items = hint_string.split(",")
	var idx = 0
	for item in items:
		var k = item
		var v = idx
		if ":" in item:
			var parts = item.split(":")
			k = parts[0]
			v = int(parts[1])
		else:
			idx += 1

		# 如果数值匹配，返回去除空白和引号的纯正键名
		if v == val:
			return k.strip_edges().replace('"', "")

	return str(val)  # 如果没有匹配的枚举，兜底返回数字


func _fuzzy_match(input: String, target: String) -> bool:
	return input.replace("_", "").replace(" ", "").to_lower() == target.replace("_", "").replace(" ", "").to_lower()
