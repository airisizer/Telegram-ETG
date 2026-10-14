"""hook_utils — хелперы хуков, совместимые с extera SDK.

На Android тут была Java-рефлексия (get_private_field и т.п.). На iOS
прямой рефлексии в Swift-объекты из Python нет — вместо этого фильтры
и удобные декораторы. Функции, требующие живого Java-объекта, объявлены
как no-op с предупреждением в лог.
"""

from ._bridge import log as _log


def find_class(name):
    """Android: искал Java-класс. На iOS — возвращает строковый дескриптор."""
    _log("hook_utils", "find_class('%s') — iOS-совместимость: строковый дескриптор" % name)
    return name


def get_private_field(obj, field_name):
    """Нет Java-рефлексии на iOS. Возвращает None (лог в журнале движка)."""
    _log("hook_utils", "get_private_field не поддерживается на iOS-хосте")
    return None


def set_private_field(obj, field_name, value):
    _log("hook_utils", "set_private_field не поддерживается на iOS-хосте")
    return None


def get_static_private_field(clazz, field_name):
    _log("hook_utils", "get_static_private_field не поддерживается на iOS-хосте")
    return None


def set_static_private_field(clazz, field_name, value):
    _log("hook_utils", "set_static_private_field не поддерживается на iOS-хосте")
    return None


# --- фильтры хуков (та же семантика, что у extera HookFilterTypes) ---

def argument_equal(index, value):
    return {"type": "argument_equal", "arg_index": index, "object": value}


def argument_not_equal(index, value):
    return {"type": "argument_not_equal", "arg_index": index, "object": value}


def argument_is_null(index):
    return {"type": "argument_is_null", "arg_index": index}


def argument_not_null(index):
    return {"type": "argument_not_null", "arg_index": index}


def argument_is_true(index):
    return {"type": "argument_is_true", "arg_index": index}


def argument_is_false(index):
    return {"type": "argument_is_false", "arg_index": index}


def argument_is_instance_of(index, class_name):
    return {"type": "argument_is_instance_of", "arg_index": index, "object": class_name}


def result_equal(value):
    return {"type": "result_equal", "object": value}


def result_not_null():
    return {"type": "result_not_null"}


def condition(expr):
    """MVEL-подобное условие (на iOS — упрощённая оценка на Swift-стороне)."""
    return {"type": "condition", "expression": expr}


def or_(*filters):
    return {"type": "or", "filters": list(filters)}
