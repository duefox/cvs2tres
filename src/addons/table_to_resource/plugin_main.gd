@tool
extends EditorPlugin

var import_plugin


func _enter_tree():
	# 加载核心逻辑脚本
	import_plugin = preload("res://addons/table_to_resource/csv_importer.gd").new()
	add_import_plugin(import_plugin)


func _exit_tree():
	# 清理插件
	remove_import_plugin(import_plugin)
	import_plugin = null
