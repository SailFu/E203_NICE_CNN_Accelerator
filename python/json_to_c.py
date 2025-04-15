import json

def array_to_c_string(obj, indent=0):
    """
    将嵌套 list 转成分行、带缩进的 C 初始化格式。
    indent 表示当前递归层级，用于控制输出缩进。
    """
    # 每层输出的缩进空格数
    indent_str = "" * indent

    if isinstance(obj, list):
        # 处理 list
        lines = []
        lines.append("{")   # 当前层的开括号
        for i, element in enumerate(obj):
            # 下一层要多缩进一层
            element_str = array_to_c_string(element, indent + 1)
            # 每个元素都放在一行
            lines.append(f"{indent_str}{element_str},")
        # 去掉最后一个元素后多余的逗号也可以，但无伤大雅，一般编译器会容忍
        # 也可以在循环里只对 i < len(obj)-1 的情况加逗号。
        lines.append(f"{indent_str}}}")   # 当前层的闭括号
        return "".join(lines)
    else:
        # 处理数字
        return str(obj)


def main():
    json_file = "./python/data.txt"
    with open(json_file, "r", encoding="utf-8") as f:
        data = json.load(f)

    c_array_str = array_to_c_string(data, 0)

    # 指定固定大小
    c_code = "static int arr[5][1][3][3] = " + c_array_str + ";\n"

    print(c_code)
    with open("converted_array.h", "w", encoding="utf-8") as out:
        out.write(c_code)

if __name__ == "__main__":
    main()
