@tool
extends EditorImportPlugin


# 定义唯一名称和显示名称
func _get_importer_name():
	return "rock.table_to_resource"


func _get_visible_name():
	return "Table to Resource (按行导出)"


func _get_recognized_extensions():
	return ["csv"]


func _get_save_extension():
	return "res"  # 这是一个占位后缀，实际文件会生成在指定目录


func _get_resource_type():
	return "Resource"


# --- 1. 定义导入面板的选项 ---
func _get_import_options(path, preset_index):
	return [
		# 目标数据类脚本路径（如 res://data/item_data.gd）
		{"name": "target_class_script", "default_value": "", "property_hint": PROPERTY_HINT_FILE, "hint_string": "*.gd"},
		# 导出文件夹（如 res://resources/items/）
		{"name": "export_folder", "default_value": "res://exported_resources/", "property_hint": PROPERTY_HINT_DIR},
		# 用作文件名的字段（如 item_id）
		{"name": "id_field_name", "default_value": "item_id"}
	]


func _get_preset_count():
	return 1


func _get_preset_name(i):
	return "默认配置"


# --- 2. 核心执行逻辑 ---
func _import(source_file, save_path, options, platform_variants, gen_files):
	# 获取用户配置
	var script_path = options["target_class_script"]
	var export_dir = options["export_folder"]
	var id_field = options["id_field_name"]

	# 检查配置有效性
	if script_path == "" or not FileAccess.file_exists(script_path):
		printerr("[TableToRes] 错误：未指定有效的目标类脚本！")
		return ERR_FILE_CANT_OPEN

	# 动态加载目标脚本类
	var TargetScript = load(script_path)
	if not TargetScript:
		return ERR_PARSE_ERROR

	# 准备目录
	if not DirAccess.dir_exists_absolute(export_dir):
		DirAccess.make_dir_recursive_absolute(export_dir)

	# 读取 CSV
	var file = FileAccess.open(source_file, FileAccess.READ)
	if not file:
		return FAILED

	var headers = Array(file.get_csv_line())  # 第一行作为表头
	var id_index = headers.find(id_field)

	if id_index == -1:
		printerr("[TableToRes] 错误：在 CSV 表头中找不到 ID 字段 '%s'" % id_field)
		return ERR_INVALID_DATA

	# 遍历每一行数据
	while !file.eof_reached():
		var row = file.get_csv_line()
		if row.size() < headers.size() or row[0].strip_edges() == "":
			continue  # 跳过空行

		# --- A. 实例化目标类 ---
		var instance = TargetScript.new()

		# --- B. 填充属性 ---
		for i in range(headers.size()):
			var prop_name = headers[i].strip_edges()
			var raw_value = row[i]

			# 仅当脚本中有这个变量时才赋值
			if prop_name in instance:
				# 获取该属性在脚本中定义的类型（用于自动转换）
				var target_val = instance.get(prop_name)
				var type_id = typeof(target_val)

				# 智能类型转换
				var final_value = _convert_string_to_type(raw_value, type_id)
				instance.set(prop_name, final_value)

		# --- C. 保存单个资源 ---
		var file_name = row[id_index]
		var final_path = export_dir.path_join(file_name + ".tres")

		# 保存并记录
		var err = ResourceSaver.save(instance, final_path)
		if err == OK:
			pass
			# print("生成资源: ", final_path)
		else:
			printerr("保存失败: ", final_path)

	# 返回一个空资源给 Godot 的导入系统作为占位符
	return ResourceSaver.save(Resource.new(), "%s.%s" % [save_path, _get_save_extension()])


# --- 3. 辅助函数：类型转换 ---
func _convert_string_to_type(val_str: String, target_type: int):
	match target_type:
		TYPE_INT:
			return int(val_str)
		TYPE_FLOAT:
			return float(val_str)
		TYPE_BOOL:
			return val_str.to_lower() == "true" or val_str == "1"
		TYPE_STRING:
			return val_str
		TYPE_OBJECT:
			# 特殊处理 AtlasTexture: "res://path.png:0,0,32,32"
			if val_str.contains(":") and val_str.contains(","):
				var parts = val_str.split(":")
				var path = parts[0]
				var rect_parts = parts[1].split(",")

				if rect_parts.size() == 4:
					var atlas = AtlasTexture.new()
					atlas.atlas = load(path)
					atlas.region = Rect2(float(rect_parts[0]), float(rect_parts[1]), float(rect_parts[2]), float(rect_parts[3]))
					return atlas

			# 默认处理为资源路径加载
			if ResourceLoader.exists(val_str):
				return load(val_str)
			return null

	return val_str
