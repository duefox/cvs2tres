@tool
extends Control

# =========================================================
# UI 节点绑定
# =========================================================

# --- 正向导入 (CSV -> Tres) ---
@onready var importer_path_line: LineEdit = %ImporterPath
@onready var related_path_line: LineEdit = %RelatedPath
@onready var emporter_path_edit: TextEdit = %EmporterPath
@onready var class_map_path: TextEdit = %ClassMapPath
@onready var id_option_btn: OptionButton = %IdOptionBtn

# --- 逆向导出 (Tres -> CSV) ---
@onready var tres_path: LineEdit = %TresPath
@onready var output_path: LineEdit = %OutputPath
@onready var output_class_map_path: TextEdit = %OutputClassMapPath

@onready var tab_bar: TabBar = %TabBar
@onready var to_cvs_panel: Panel = %ToCvsPanel
@onready var to_tres_panel: Panel = %ToTresPanel
@onready var log_label: RichTextLabel = %LogLabel

# =========================================================
# 逻辑类与弹窗实例
# =========================================================

var _core: TableToResCore

# 弹窗 (正向)
var _dlg_csv: FileDialog
var _dlg_dir: FileDialog
var _dlg_script: FileDialog
var _dlg_scan: FileDialog

# 弹窗 (逆向)
var _dlg_export_scan: FileDialog
var _dlg_output: FileDialog
var _dlg_output_class_scan: FileDialog


func _ready() -> void:
	_core = TableToResCore.new()
	_core.log_updated.connect(_on_log_updated)
	_setup_dialogs()
	var btn_export = find_child("BtnOutputCVS", true, false)
	if btn_export and not btn_export.pressed.is_connected(_on_btn_output_cvs_pressed):
		btn_export.pressed.connect(_on_btn_output_cvs_pressed)

	if is_instance_valid(tab_bar):
		_update_tab_visibility(tab_bar.current_tab)
		
	# 自动检测并加载默认的映射字典
	_auto_load_default_class_map()


# =========================================================
# 弹窗初始化 (使用系统原生窗口)
# =========================================================
func _setup_dialogs():
	# --- 正向：选择 CSV ---
	if _dlg_csv:
		_dlg_csv.queue_free()
	_dlg_csv = FileDialog.new()
	_config_dialog(_dlg_csv, "选择导入的 CSV 表格", FileDialog.FILE_MODE_OPEN_FILE)
	_dlg_csv.add_filter("*.csv", "CSV 表格")
	_dlg_csv.file_selected.connect(_on_csv_selected)
	add_child(_dlg_csv)

	# --- 正向：选择 资源导出目录 ---
	if _dlg_dir:
		_dlg_dir.queue_free()
	_dlg_dir = FileDialog.new()
	_config_dialog(_dlg_dir, "选择资源导出文件夹", FileDialog.FILE_MODE_OPEN_DIR)
	_dlg_dir.dir_selected.connect(func(path): emporter_path_edit.text = path)
	add_child(_dlg_dir)

	# --- 正向：选择 关联脚本 ---
	if _dlg_script:
		_dlg_script.queue_free()
	_dlg_script = FileDialog.new()
	_config_dialog(_dlg_script, "选择关联的数据类脚本 (.gd)", FileDialog.FILE_MODE_OPEN_FILE)
	_dlg_script.access = FileDialog.ACCESS_RESOURCES
	_dlg_script.add_filter("*.gd", "GDScript 数据类")
	_dlg_script.file_selected.connect(func(path): related_path_line.text = path)
	add_child(_dlg_script)

	# --- 正向：选择 扫描映射字典的目录 ---
	if _dlg_scan: _dlg_scan.queue_free()
	_dlg_scan = FileDialog.new()
	_config_dialog(_dlg_scan, "选择需要扫描脚本的根目录", FileDialog.FILE_MODE_OPEN_DIR)
	_dlg_scan.dir_selected.connect(func(dir_path):
		# [修改] 使用统一的默认路径
		var save_path = TableToResCore.DEFAULT_MAP_PATH 
		_core.build_class_map(dir_path, save_path)
		class_map_path.text = save_path
		output_class_map_path.text = save_path # 同步更新另一页的UI
	)
	add_child(_dlg_scan)

	# =====================

	# --- 逆向：选择 读取Tres的目录 ---
	if _dlg_export_scan:
		_dlg_export_scan.queue_free()
	_dlg_export_scan = FileDialog.new()
	_config_dialog(_dlg_export_scan, "选择要导出的资源 (.tres) 文件夹", FileDialog.FILE_MODE_OPEN_DIR)
	_dlg_export_scan.dir_selected.connect(func(path): tres_path.text = path)
	add_child(_dlg_export_scan)

	# --- 逆向：设置 导出的CSV文件 (SAVE_FILE 模式) ---
	if _dlg_output:
		_dlg_output.queue_free()
	_dlg_output = FileDialog.new()
	_config_dialog(_dlg_output, "另存为 CSV 表格", FileDialog.FILE_MODE_SAVE_FILE)
	_dlg_output.add_filter("*.csv", "CSV 表格")
	_dlg_output.file_selected.connect(func(path): output_path.text = path)
	add_child(_dlg_output)

	# --- 逆向：选择 扫描映射字典的目录 (复用逻辑) ---
	if _dlg_output_class_scan: _dlg_output_class_scan.queue_free()
	_dlg_output_class_scan = FileDialog.new()
	_config_dialog(_dlg_output_class_scan, "选择需要扫描脚本的根目录", FileDialog.FILE_MODE_OPEN_DIR)
	_dlg_output_class_scan.dir_selected.connect(func(dir_path):
		# [修改] 使用统一的默认路径
		var save_path = TableToResCore.DEFAULT_MAP_PATH
		_core.build_class_map(dir_path, save_path)
		output_class_map_path.text = save_path
		class_map_path.text = save_path # 同步更新另一页的UI
	)
	add_child(_dlg_output_class_scan)


func _config_dialog(dlg: FileDialog, title: String, mode: int):
	dlg.use_native_dialog = true
	dlg.min_size = Vector2(600, 400)
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = title
	dlg.file_mode = mode


# =========================================================
# 交互信号响应
# =========================================================


# --- CSV 解析下拉表头 ---
func _on_csv_selected(path: String):
	importer_path_line.text = path
	id_option_btn.clear()
	var headers = _core.get_csv_headers(path)
	if headers.is_empty():
		_add_log("警告：CSV 为空或无法读取。", TableToResCore.LogType.WARNING)
		return
	for h in headers:
		id_option_btn.add_item(h)
	for i in range(headers.size()):
		if headers[i].to_lower() in ["id", "item_id", "key", "name"]:
			id_option_btn.selected = i
			break


# --- 正向按钮组 ---
func _on_btn_importer_pressed():
	_dlg_csv.popup_centered_ratio(0.6)


func _on_btn_related_pressed():
	_dlg_script.popup_centered_ratio(0.6)


func _on_btn_emporter_pressed():
	_dlg_dir.popup_centered_ratio(0.6)


func _on_btn_scan_pressed():
	_dlg_scan.popup_centered_ratio(0.6)


func _on_btn_execute_pressed():
	if _validate_import_inputs():
		_core.execute_conversion(
			importer_path_line.text, emporter_path_edit.text, id_option_btn.get_item_text(id_option_btn.selected), related_path_line.text, class_map_path.text, false
		)


func _on_btn_update_pressed():
	if _validate_import_inputs():
		_core.execute_conversion(
			importer_path_line.text, emporter_path_edit.text, id_option_btn.get_item_text(id_option_btn.selected), related_path_line.text, class_map_path.text, true
		)


func _validate_import_inputs() -> bool:
	if importer_path_line.text.is_empty() or related_path_line.text.is_empty() or emporter_path_edit.text.is_empty() or id_option_btn.item_count == 0:
		_add_log("错误：正向导入参数不完整。", TableToResCore.LogType.ERROR)
		return false
	return true


# --- 逆向按钮组 ---
func _on_btn_tres_browse_pressed():
	_dlg_export_scan.popup_centered_ratio(0.6)


func _on_btn_output_setting_pressed():
	_dlg_output.popup_centered_ratio(0.6)


func _on_btn_output_scan_pressed():
	_dlg_output_class_scan.popup_centered_ratio(0.6)


# [核心] 逆向执行导出
func _on_btn_output_cvs_pressed():
	if tres_path.text.is_empty():
		_add_log("错误：请选择要导出的资源文件夹。", TableToResCore.LogType.ERROR)
		return
	if output_path.text.is_empty():
		_add_log("错误：请设置输出的 CSV 文件路径。", TableToResCore.LogType.ERROR)
		return
	_core.execute_export_to_csv(tres_path.text, output_path.text)
	

# 自动加载默认字典的逻辑
func _auto_load_default_class_map() -> void:
	if FileAccess.file_exists(TableToResCore.DEFAULT_MAP_PATH):
		if is_instance_valid(class_map_path):
			class_map_path.text = TableToResCore.DEFAULT_MAP_PATH
		if is_instance_valid(output_class_map_path):
			output_class_map_path.text = TableToResCore.DEFAULT_MAP_PATH
		
		# 延迟一帧打印日志，确保 UI 已经完全就绪
		call_deferred("_add_log", "已自动检测并回填类名映射字典。", TableToResCore.LogType.SUCCESS)


# --- 日志模块 ---
func _on_log_updated(msg: String, type: int):
	_add_log(msg, type)


func _add_log(msg: String, type: int = TableToResCore.LogType.INFO):
	var color = "white"
	match type:
		TableToResCore.LogType.SUCCESS:
			color = "#00ff00"
		TableToResCore.LogType.ERROR:
			color = "#ff4444"
		TableToResCore.LogType.WARNING:
			color = "#ffff00"
	if is_instance_valid(log_label):
		log_label.append_text("[color=%s]%s[/color]\n" % [color, msg])


# =========================================================
# 交互信号响应
# =========================================================


# ---Tab 页切换逻辑 ---
func _on_tab_bar_tab_clicked(tab: int) -> void:
	_update_tab_visibility(tab)


func _update_tab_visibility(tab_idx: int) -> void:
	# 确保节点有效以防报错
	if not is_instance_valid(to_tres_panel) or not is_instance_valid(to_cvs_panel):
		return

	# 假设 Tab 0 是 "正向生成"，Tab 1 是 "逆向导出"
	if tab_idx == 0:
		to_tres_panel.visible = true
		to_cvs_panel.visible = false
	elif tab_idx == 1:
		to_tres_panel.visible = false
		to_cvs_panel.visible = true
