# LunaNexa workflow templates.
#
# This package ships only example_workflows/*.json for the ComfyUI template
# browser. It defines no nodes on purpose: the graphs use ComfyUI core nodes
# (SaveVideo, MarkdownNote) plus one node from ComfyUI-vLLM-Omni
# (VLLMOmniGenerateVideo).
#
# ComfyUI records a module directory in nodes.LOADED_MODULE_DIRS as soon as its
# __init__.py imports, and that list is what registers the static route
# /api/workflow_templates/<module name>. Declaring the empty mappings below is
# what keeps load_custom_node() from logging the module as skipped for having
# no node definitions.
NODE_CLASS_MAPPINGS = {}
NODE_DISPLAY_NAME_MAPPINGS = {}
